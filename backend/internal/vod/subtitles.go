// Package vod handles server-side composition of livestream replay
// videos. Worker reads the raw FLV plus the timeline (chat_messages +
// live_events) and produces a final MP4 with overlays burned in via
// FFmpeg, so a viewer who downloads / shares the MP4 outside the app
// still sees what happened during the live (chat, host pin, coupons,
// bot toggle).
//
// This file: ASS subtitle generation for the chat overlay. Chat is
// rendered via FFmpeg's libass subtitle filter rather than as PNG
// overlays because there's typically a lot of chat (hundreds of lines
// per session) and ASS keeps the FFmpeg filter graph small (one input
// vs hundreds). Pin / coupon / bot overlays are rendered as PNGs and
// composited via the `overlay` filter — see overlay.go.
package vod

import (
	"fmt"
	"strings"
	"time"

	"github.com/tropia/backend/internal/live"
)

// ChatMaxStack is how many chat lines stack vertically at once before
// the oldest scrolls off the top. Each line stays visible from the
// moment it's sent until it gets pushed off the stack by `ChatMaxStack`
// newer messages, OR until the video ends — no fixed lifetime, so a
// quiet stream still shows the last chat for the whole video instead
// of going blank.
const ChatMaxStack = 6

// ASS color is BGR hex with the &H00 prefix (00 = fully opaque).
const (
	colorWhite     = "&H00FFFFFF" // viewers
	colorHostGold  = "&H0000D7FF" // host messages — gold (BGR: 00=B,D7=G,FF=R)
	colorBotLilac  = "&H00FF80C0" // bot messages — lavender
)

// BuildChatASS turns a chronologically-sorted list of chat messages
// into an ASS subtitle script suitable for FFmpeg's `subtitles` filter.
//
// `sessionStart` is the wall-clock time the stream started — every
// chat message's `created_at` is converted to an offset from this.
// `videoDuration` is the total video length; the very last chat line
// stays visible until this point (so a quiet stream's chat persists).
// Width/height are the video resolution (used for ASS PlayRes).
//
// The output is UTF-8 text. The caller writes it to disk and passes
// the path to FFmpeg.
func BuildChatASS(chats []live.ChatMessage, sessionStart time.Time, videoDuration time.Duration, width, height int) string {
	var b strings.Builder

	// ── Script Info ─────────────────────────────────────────────────
	fmt.Fprintf(&b, "[Script Info]\nScriptType: v4.00+\nPlayResX: %d\nPlayResY: %d\nWrapStyle: 2\nScaledBorderAndShadow: yes\n\n",
		width, height)

	// ── Styles ─────────────────────────────────────────────────────
	// Default chat style: bottom-left aligned (alignment=1), white text
	// with semi-transparent black background (BorderStyle=3 = "box")
	// to keep readability over any video content. Font size scales with
	// video height — 28pt at 1920p, smaller for shorter videos.
	fontSize := height / 60
	if fontSize < 18 {
		fontSize = 18
	}
	b.WriteString("[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n")
	fmt.Fprintf(&b,
		"Style: ChatBox,Arial,%d,%s,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,3,2,0,1,40,40,40,1\n\n",
		fontSize, colorWhite)

	// ── Events ─────────────────────────────────────────────────────
	b.WriteString("[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")

	lineHeight := fontSize + 16 // px between stacked chat lines
	videoEndMs := videoDuration.Milliseconds()
	if videoEndMs <= 0 {
		videoEndMs = 1 << 30 // effectively infinite if caller didn't pass duration
	}

	// For each chat message, walk its stack positions 0..maxStack-1.
	// Position k means the line has been pushed up by k newer chats.
	// segment timing for line i at position pos:
	//   start = chats[i+pos].created_at  (or chats[i] if pos == 0)
	//   end   = chats[i+pos+1].created_at, or videoEndMs if no more chats
	// When (i+pos+1) >= len(chats), there's no further push — the
	// line stays at this final position until the video ends and we
	// stop iterating.
	for i, m := range chats {
		for pos := 0; pos < ChatMaxStack; pos++ {
			pusherIdx := i + pos // 0..maxStack-1 → which message defined "when we got pushed to this pos"
			if pusherIdx >= len(chats) {
				break
			}
			var segStart int64
			if pos == 0 {
				segStart = chats[i].CreatedAt.Sub(sessionStart).Milliseconds()
			} else {
				segStart = chats[pusherIdx].CreatedAt.Sub(sessionStart).Milliseconds()
			}
			if segStart < 0 {
				segStart = 0
			}

			var segEnd int64
			if pusherIdx+1 < len(chats) {
				segEnd = chats[pusherIdx+1].CreatedAt.Sub(sessionStart).Milliseconds()
			} else {
				segEnd = videoEndMs
			}
			if segEnd <= segStart {
				continue
			}

			// Base 500px above bottom. Earlier values (180, then 320)
			// still tucked the lowest chat line right against the
			// browser MP4 player's controls bar (timestamp + play
			// button render on top of the video, and on a vertical
			// 1080×1920 source 320 only ≈17% from bottom — not enough
			// margin when the controls overlay appears). 500 sits the
			// bottom of the stack at ≈26% from the bottom — clear of
			// the controls without crowding the host's face.
			marginV := 500 + pos*lineHeight
			writeChatDialogue(&b, segStart, segEnd, marginV, m)

			// If there's no chat after this one, our line stays at
			// this final position until video end — don't generate
			// segments for higher stack positions.
			if pusherIdx+1 >= len(chats) {
				break
			}
		}
	}

	return b.String()
}

// writeChatDialogue emits one ASS Dialogue line. Username gets a color
// tag prefix based on role (host = gold, bot = lavender, others = white).
func writeChatDialogue(b *strings.Builder, startMs, endMs int64, marginV int, m live.ChatMessage) {
	// Bot first: an AI bot message has is_host=true (it speaks on
	// behalf of the host) but should be visually distinct from a real
	// human host. Check the type marker before the host flag.
	nameColor := colorWhite
	switch {
	case m.Type == "bot":
		nameColor = colorBotLilac
	case m.IsHost != nil && *m.IsHost:
		nameColor = colorHostGold
	}

	// ASS escape: { and } are control chars; commas split fields; \N is
	// line break. We strip these from user content to prevent injection
	// into the dialogue format.
	user := sanitizeASS(m.Username)
	msg := sanitizeASS(m.Message)

	// Truncate long lines: ASS `WrapStyle=2` (set in BuildChatASS) means
	// long text doesn't auto-wrap, it just clips at the frame boundary.
	// On a 1080-wide source with font ≈32 and MarginL/R=40, ~60 visible
	// chars fit before the line runs off the right edge. Cap user + ": " +
	// msg at 60 chars and append an ellipsis so the chat stays inside
	// the video frame. (Switching to wrapping would risk wrapped lines
	// overlapping the chat row above them — truncation is simpler.)
	const maxVisible = 60
	userR := []rune(user)
	msgR := []rune(msg)
	if len(userR)+2+len(msgR) > maxVisible {
		avail := maxVisible - len(userR) - 2 - 1 // -1 for the ellipsis
		if avail < 5 {
			avail = 5
		}
		if len(msgR) > avail {
			msg = string(msgR[:avail]) + "…"
		}
	}

	// Inline color override for the username via {\1c&HBGR&}, then reset
	// to style default for the message body.
	text := fmt.Sprintf("{\\1c%s\\b1}%s:{\\b0\\1c%s} %s",
		nameColor, user, colorWhite, msg)

	fmt.Fprintf(b, "Dialogue: 0,%s,%s,ChatBox,,0,0,%d,,%s\n",
		assTime(startMs), assTime(endMs), marginV, text)
}

// assTime formats ms as "H:MM:SS.cc" — ASS uses centiseconds.
func assTime(ms int64) string {
	if ms < 0 {
		ms = 0
	}
	h := ms / 3600000
	rem := ms % 3600000
	m := rem / 60000
	rem = rem % 60000
	s := rem / 1000
	cs := (rem % 1000) / 10
	return fmt.Sprintf("%d:%02d:%02d.%02d", h, m, s, cs)
}

// sanitizeASS strips ASS control chars + collapses newlines so user
// input can't break out of the Text field or inject overrides.
func sanitizeASS(s string) string {
	s = strings.ReplaceAll(s, "\r", "")
	s = strings.ReplaceAll(s, "\n", " ")
	s = strings.ReplaceAll(s, "{", "(")
	s = strings.ReplaceAll(s, "}", ")")
	s = strings.ReplaceAll(s, "\\", "/")
	return s
}
