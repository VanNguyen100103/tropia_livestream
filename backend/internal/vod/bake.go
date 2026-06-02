package vod

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/tropia/backend/internal/live"
)

// BakeInput is everything the bake pipeline needs to produce one
// composited MP4. Caller (worker) fills it from DB lookups before
// calling Bake.
type BakeInput struct {
	SessionID    uuid.UUID
	FLVPath      string    // absolute path to source FLV on disk
	SessionStart time.Time // wall-clock t0; used to compute event offsets
	Chats        []live.ChatMessage
	Events       []live.LiveEvent
	Products     []live.SessionProduct // mirrored as a left-side carousel overlay
	// VideoDuration controls how long the LAST chat line persists on
	// screen (it stays from its post time to videoEnd). Caller passes
	// session.ended_at - started_at; if 0, chat falls back to last
	// known event time + padding.
	VideoDuration time.Duration
	// WorkDir is where intermediate files (ASS, PNGs, temp MP4) are
	// written. Caller picks a tmp dir and cleans up after Bake returns.
	WorkDir string
	// Resolution of the source video; the ASS subtitle PlayRes is set
	// to match so libass scales correctly. If 0, default 1080x1920
	// (vertical mobile orientation).
	Width  int
	Height int
	// WatermarkText is burned into the bottom-right corner of every
	// frame for forensic provenance — when a clip surfaces on YouTube
	// or other platforms, the watermark proves it originated on Tropia
	// and (with the session id substring) identifies which session.
	// Threat 3 (recording + reupload). Empty disables the watermark.
	WatermarkText string
	// WatermarkFontPath overrides the auto-detected system font for
	// the watermark. Leave empty to let Bake probe common locations
	// (Windows Arial, Linux DejaVu, macOS Helvetica). If nothing is
	// found and this is empty, the watermark is silently skipped with
	// a warning log — the bake still succeeds without it.
	WatermarkFontPath string
	Logger            *slog.Logger
}

// Bake runs the FFmpeg pipeline: re-encode FLV → MP4 with chat
// subtitles + host-action overlays (pin / coupon / bot chip) burned in.
// Returns absolute path to the final MP4.
//
// This is the SLOW path (full re-encode, ~1× realtime on a laptop CPU).
// For a 30-min stream, expect ~30 min of worker CPU. Plan accordingly.
func Bake(ctx context.Context, in BakeInput) (string, error) {
	if in.Logger == nil {
		in.Logger = slog.Default()
	}
	if in.Width == 0 {
		in.Width = 1080
	}
	if in.Height == 0 {
		in.Height = 1920
	}
	if err := os.MkdirAll(in.WorkDir, 0o755); err != nil {
		return "", fmt.Errorf("mkdir work: %w", err)
	}

	// FLVPath may be relative to the caller's CWD (worker passes
	// "../infra/dvr/...") but we cd into WorkDir below to dodge the
	// Windows drive-colon parser bug in -vf. Make FLVPath absolute so
	// FFmpeg still finds the input from the new CWD.
	if abs, err := filepath.Abs(in.FLVPath); err == nil {
		in.FLVPath = abs
	}

	// Determine the video's end timestamp (ms). Caller's VideoDuration
	// is the source of truth; if missing, fall back to the latest
	// known signal (last event / last chat) + padding.
	endMs := in.VideoDuration.Milliseconds()
	if endMs <= 0 {
		for _, e := range in.Events {
			if e.StreamOffsetMs > endMs {
				endMs = e.StreamOffsetMs
			}
		}
		for _, m := range in.Chats {
			if t := m.CreatedAt.Sub(in.SessionStart).Milliseconds(); t > endMs {
				endMs = t
			}
		}
		endMs += 8000
	}
	videoDuration := time.Duration(endMs) * time.Millisecond

	// 1. Build chat ASS subtitle file. Gift messages are excluded here —
	// they're rendered as their own banner overlay (PrepareOverlays) so
	// they don't appear twice (subtitle + banner).
	chatsForASS := make([]live.ChatMessage, 0, len(in.Chats))
	for _, m := range in.Chats {
		if m.Type == "gift" {
			continue
		}
		chatsForASS = append(chatsForASS, m)
	}
	assText := BuildChatASS(chatsForASS, in.SessionStart, videoDuration, in.Width, in.Height)
	assPath := filepath.Join(in.WorkDir, "chat.ass")
	if err := os.WriteFile(assPath, []byte(assText), 0o644); err != nil {
		return "", fmt.Errorf("write ass: %w", err)
	}

	// 2. Render PNG overlays for pin / coupon / bot.
	flat := flattenEvents(in.Events, in.SessionStart)
	assets, err := PrepareOverlays(ctx, flat, in.WorkDir, endMs)
	if err != nil {
		return "", fmt.Errorf("prepare overlays: %w", err)
	}

	// 2b. Render the product-list overlay (one PNG, displayed for the
	// entire video duration). Mirrors the left-side carousel of the
	// live host screen.
	if len(in.Products) > 0 {
		prods := make([]Product, 0, len(in.Products))
		for _, p := range in.Products {
			imgURL := ""
			if p.ImageURL != nil {
				imgURL = *p.ImageURL
			}
			prods = append(prods, Product{Name: p.ProductName, SalePrice: p.SalePrice, ImageURL: imgURL})
		}
		productListPath := filepath.Join(in.WorkDir, "products.png")
		if err := RenderProductList(ctx, prods, productListPath); err != nil {
			in.Logger.Warn("product list render failed; skipping", "err", err)
		} else {
			assets = append(assets, OverlayAsset{
				Path: productListPath, Type: "products", StartMs: 0, EndMs: endMs,
			})
		}
	}

	in.Logger.Info("vod bake: assets ready",
		"chats", len(in.Chats), "events", len(in.Events),
		"products", len(in.Products), "overlays", len(assets),
	)

	// 3. Build FFmpeg command.
	//
	// One -i per overlay PNG, plus the input video. Filter graph chains
	// subtitles → overlay(pin1) → overlay(coupon1) → ... → final stream.
	// Each overlay uses enable='between(t,start,end)' so it's only
	// drawn during its window. Position depends on type:
	//   - pin:    bottom-left (24, H-pinH-200)
	//   - coupon: top-right   (W-couponW-24, 96)
	//   - bot:    top-right (W-botChipW-24, 24)
	//
	// Windows FFmpeg parses `:` inside the -vf arg as an option
	// separator, so we cd into WorkDir and reference files by basename.
	outPath := filepath.Join(in.WorkDir, "baked.mp4")
	assBasename := filepath.Base(assPath)

	args := []string{"-y", "-i", in.FLVPath}
	for _, a := range assets {
		args = append(args, "-i", filepath.Base(a.Path))
	}

	// Build filter_complex.
	var fg strings.Builder
	prev := "[0:v]"
	// First: subtitles.
	fmt.Fprintf(&fg, "%ssubtitles=%s[v0];", prev, assBasename)
	prev = "[v0]"

	for i, a := range assets {
		inLabel := fmt.Sprintf("[%d:v]", i+1) // overlay input streams start at index 1
		outLabel := fmt.Sprintf("[v%d]", i+1)
		x, y := overlayExpr(a.Type)
		startSec := float64(a.StartMs) / 1000.0
		endSec := float64(a.EndMs) / 1000.0
		fmt.Fprintf(&fg, "%s%soverlay=x=%s:y=%s:enable='between(t\\,%.3f\\,%.3f)'%s;",
			prev, inLabel, x, y, startSec, endSec, outLabel)
		prev = outLabel
	}
	// Forensic watermark — drawn LAST so it sits above every overlay.
	// We use a numeric label index continuing past the overlay count
	// (assets are indexed v1..vN by the loop above) so rebuildWithVOut
	// finds and renames it to [vout] without colliding.
	watermarkApplied := false
	wmText := in.WatermarkText
	if wmText == "" {
		wmText = "TROPIA · " + shortID(in.SessionID.String())
	}
	if fontPath := resolveWatermarkFont(in.WatermarkFontPath); fontPath != "" {
		wmLabel := fmt.Sprintf("[v%d]", len(assets)+1)
		fmt.Fprintf(&fg,
			"%sdrawtext=fontfile='%s':text='%s':fontcolor=white@0.75:fontsize=28:box=1:boxcolor=black@0.4:boxborderw=8:x=W-tw-32:y=H-th-32%s;",
			prev, escapeFFmpegPath(fontPath), escapeFFmpegText(wmText), wmLabel)
		prev = wmLabel
		watermarkApplied = true
	} else {
		in.Logger.Warn("vod bake: no system font found — watermark skipped",
			"session_id", in.SessionID,
			"hint", "set BakeInput.WatermarkFontPath to enable forensic watermark")
	}
	_ = watermarkApplied
	// Drop trailing `;` and label the final output as [vout].
	filterStr := strings.TrimSuffix(fg.String(), ";")
	// Rename prev → [vout] for the -map.
	filterStr = filterStr + "[vout]"
	// The above puts an extra [vout] after the final label — fix by
	// rewriting: replace the last "[vN]" with "[vout]" instead of
	// appending. Easier path: rebuild with proper final label.
	filterStr = rebuildWithVOut(prev, fg.String())

	args = append(args,
		"-filter_complex", filterStr,
		"-map", "[vout]",
		"-map", "0:a?",
		"-c:v", "libx264",
		"-preset", "veryfast",
		"-crf", "23",
		"-c:a", "copy",
		"-movflags", "+faststart",
		outPath,
	)

	cmd := exec.CommandContext(ctx, "ffmpeg", args...)
	cmd.Dir = in.WorkDir
	start := time.Now()
	out, err := cmd.CombinedOutput()
	if err != nil {
		tail := string(out)
		if len(tail) > 1200 {
			tail = "..." + tail[len(tail)-1200:]
		}
		return "", fmt.Errorf("ffmpeg bake failed: %w — %s", err, tail)
	}
	in.Logger.Info("vod bake: ffmpeg done",
		"session_id", in.SessionID,
		"out", outPath,
		"dur", time.Since(start).Truncate(time.Millisecond),
	)
	return outPath, nil
}

// rebuildWithVOut takes the filter graph string and the last
// intermediate label (e.g. "[v3]") and rewrites every occurrence of
// that label-as-output into "[vout]" so the -map "[vout]" works. If
// there were no overlays at all, the subtitle filter alone produces
// [v0] which becomes [vout].
func rebuildWithVOut(lastLabel, graph string) string {
	graph = strings.TrimSuffix(graph, ";")
	// Replace ONLY the final `[vN]` (the output label of the last
	// filter). Since the same label appears as input to a non-existent
	// next filter only once (at the very end), simple suffix swap works.
	if strings.HasSuffix(graph, lastLabel) {
		return graph[:len(graph)-len(lastLabel)] + "[vout]"
	}
	// Fallback — append explicit copy filter.
	return graph + ";" + lastLabel + "null[vout]"
}

// shortID returns the first 8 chars of a UUID for forensic labeling
// without bloating the watermark line.
func shortID(s string) string {
	if len(s) <= 8 {
		return s
	}
	return s[:8]
}

// candidateWatermarkFonts lists the most likely places to find a usable
// truetype font for FFmpeg drawtext, in priority order. We probe one by
// one so the watermark works on dev (Windows), CI (Linux), and any
// future macOS build host without explicit configuration.
var candidateWatermarkFonts = []string{
	// Windows
	`C:\Windows\Fonts\arial.ttf`,
	`C:\Windows\Fonts\segoeui.ttf`,
	`C:\Windows\Fonts\calibri.ttf`,
	// Linux (Debian/Ubuntu)
	"/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
	"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
	"/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
	// Alpine (Docker images)
	"/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
	// macOS
	"/System/Library/Fonts/Helvetica.ttc",
	"/Library/Fonts/Arial.ttf",
}

// resolveWatermarkFont returns the first usable font path or "" if none
// were found. An explicit override always wins (caller may know their
// production AMI bundles a specific font).
func resolveWatermarkFont(override string) string {
	if override != "" {
		if _, err := os.Stat(override); err == nil {
			return override
		}
	}
	for _, p := range candidateWatermarkFonts {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

// escapeFFmpegPath rewrites a filesystem path so it survives FFmpeg's
// filter-graph parser. Windows paths in particular trip the parser
// because `:` is the option separator and `\` doubles as escape: we
// flip backslashes to forward slashes and escape the drive-letter
// colon. Single quotes are escaped because the path is wrapped in `'`.
func escapeFFmpegPath(p string) string {
	p = strings.ReplaceAll(p, `\`, `/`)
	p = strings.ReplaceAll(p, ":", `\:`)
	p = strings.ReplaceAll(p, "'", `\'`)
	return p
}

// escapeFFmpegText escapes the special chars FFmpeg's drawtext consumes
// from the `text=` value when wrapped in single quotes: backslash, colon,
// and the closing quote itself.
func escapeFFmpegText(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, "'", `\'`)
	s = strings.ReplaceAll(s, ":", `\:`)
	return s
}

// overlayExpr returns FFmpeg `overlay` filter expressions for x and y.
// Using expressions (W = main video width, w = overlay width; same for
// H/h) means positions adapt to whatever resolution the host pushed —
// 720×1280, 1080×1920, even landscape — without our caller having to
// probe the input file first.
func overlayExpr(typ string) (string, string) {
	switch typ {
	case "pin":
		// Top-center spotlight, mirrors the Flutter _PinnedSpotlight
		// (live_stream_screen.dart) which floats below the shop bar.
		// Previously rendered bottom-left (H-h-360) which collided with
		// the chat band and felt buried; viewers should see "ĐANG GHIM"
		// front and center.
		return "(W-w)/2", "80"
	case "coupon":
		// Top-right, below the LIVE badge area (~96px down).
		return "W-w-24", "96"
	case "bot":
		// Top-right corner, above the coupon banner.
		return "W-w-24", "32"
	case "products":
		// Left side, below the top-center pin banner so the two don't
		// fight for the same vertical band. `h` here is the product
		// list PNG height (varies with # of products).
		return "24", "H*0.30"
	case "gift":
		// Bottom-center, above the chat band — a transient celebratory
		// banner that doesn't permanently occupy a corner.
		return "(W-w)/2", "H*0.62"
	}
	return "24", "24"
}

// flattenEvents parses each live_events row's JSON payload into a
// LiveEventLite. SessionStart is unused here (offsets are already in
// stream_offset_ms) but kept in the signature so the call site reads
// uniformly with chat handling.
func flattenEvents(events []live.LiveEvent, _ time.Time) []LiveEventLite {
	out := make([]LiveEventLite, 0, len(events))
	for _, e := range events {
		ev := LiveEventLite{Type: e.EventType, StartMs: e.StreamOffsetMs}
		var p map[string]any
		_ = json.Unmarshal(e.Payload, &p)
		switch e.EventType {
		case "product_pin":
			ev.PinName, _ = p["product_name"].(string)
			ev.PinImageURL, _ = p["image_url"].(string)
			if v, ok := p["sale_price"].(float64); ok {
				ev.PinPrice = v
			}
		case "coupon_publish":
			ev.CouponCode, _ = p["code"].(string)
			ev.CouponType, _ = p["discount_type"].(string)
			if v, ok := p["discount_value"].(float64); ok {
				ev.CouponValue = v
			}
		case "bot_toggle":
			ev.BotEnabled, _ = p["enabled"].(bool)
		case "gift":
			ev.GiftSender, _ = p["sender_name"].(string)
			ev.GiftName, _ = p["gift_name"].(string)
			ev.GiftCode, _ = p["gift_code"].(string)
			if v, ok := p["quantity"].(float64); ok {
				ev.GiftQty = int(v)
			}
		}
		out = append(out, ev)
	}
	return out
}
