package vod

import (
	"context"
	"fmt"
	"image/color"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/fogleman/gg"
	"golang.org/x/image/font"
)

// FeedOverlayInput is the STATIC info layer burned onto an uploaded short-form
// clip to produce its downloadable / shareable copy. Only fields that don't
// change per-viewer or over time belong here: shop handle, caption, hashtags,
// a product card, voucher badges, and the Tropia watermark. The live stuff
// (like/comment counts, the flash-sale countdown, the tappable
// "Mua với Voucher" / "Xem sản phẩm" buttons) is deliberately NOT baked — it
// stays as live Flutter UI drawn over the raw clip in the feed.
type FeedOverlayInput struct {
	Width, Height int      // target video resolution; 0 ⇒ 1080×1920 (vertical)
	Handle        string   // creator/shop handle, e.g. "@Shop của A"
	Caption       string   // clip caption
	Hashtags      []string // tags without the leading '#'
	Products      []Product
	CouponLabels  []string // pre-formatted, e.g. "Giảm 5%"
	WatermarkText string   // bottom-right provenance mark; "" ⇒ "TROPIA"
	Logger        *slog.Logger

	// Action-rail fields — a static mirror of the feed's right-edge rail, baked
	// so the shared/downloaded copy still reads as a Tropia Video. Counts are a
	// SNAPSHOT at bake time (a fresh clip's are ~0, so only icons show — we never
	// stamp a stale number). AvatarURL feeds the rail head + follow (+) badge.
	AvatarURL    string
	LikeCount    int
	CommentCount int
	ShareCount   int

	// ShopHasVoucher → a static "Mua với Voucher" pill under the product card
	// (the tappable one stays live Flutter UI in-app).
	ShopHasVoucher bool
}

// RenderFeedOverlay draws the static info layer into a single transparent PNG
// the size of the target video. BakeFeedOverlay then composites it over the
// raw clip in one FFmpeg pass. The layout mirrors the feed's bottom-left
// column: voucher pills → product card → "@handle" → caption → hashtags, with
// a bottom scrim for legibility and the watermark in the corner.
func RenderFeedOverlay(ctx context.Context, in FeedOverlayInput, outPath string) error {
	if in.Logger == nil {
		in.Logger = slog.Default()
	}
	if in.Width == 0 {
		in.Width = 1080
	}
	if in.Height == 0 {
		in.Height = 1920
	}
	W, H := float64(in.Width), float64(in.Height)
	scale := W / 1080.0
	dc := gg.NewContext(in.Width, in.Height) // starts fully transparent

	// Bottom scrim — fades from transparent to ~60% black so white text stays
	// readable over a bright clip.
	grad := gg.NewLinearGradient(0, H*0.5, 0, H)
	grad.AddColorStop(0, color.RGBA{0, 0, 0, 0})
	grad.AddColorStop(1, color.RGBA{0, 0, 0, 150})
	dc.SetFillStyle(grad)
	dc.DrawRectangle(0, H*0.5, W, H*0.5)
	dc.Fill()

	margin := 0.045 * W
	blockW := W * 0.72 // leave the right rail free for the live action icons

	// Faces. If the system font is missing, loadFace errors for all sizes —
	// fail fast so the worker marks the bake 'failed' rather than emit a blank.
	handleFace, err := loadFace(34 * scale)
	if err != nil {
		return fmt.Errorf("overlay font: %w", err)
	}
	captionFace, _ := loadFace(28 * scale)
	tagFace, _ := loadFace(26 * scale)
	nameFace, _ := loadFace(28 * scale)
	priceFace, _ := loadFace(34 * scale)
	pillFace, _ := loadFace(24 * scale)
	wmFace, _ := loadFace(26 * scale)
	countFace, _ := loadFace(24 * scale) // action-rail like/comment/share counts
	badgeFace, _ := loadFace(13 * scale) // "FLASH SALE" tag across the card image

	// ── Voucher pills + product card ──
	// Anchor the card, then tuck the voucher pills just above it with a small
	// gap (mirrors the feed's CouponStrip → card spacing) instead of floating
	// them high above the card. pillH must match drawPill's pill height.
	cardTop := H * 0.60
	pillH := 44 * scale
	if len(in.CouponLabels) > 0 {
		drawPillRow(dc, in.CouponLabels, margin, cardTop-pillH-8*scale, scale, pillFace)
	}

	if len(in.Products) > 0 {
		cardH := drawFeedProductCard(dc, in.Products[0], margin, cardTop, blockW, scale, nameFace, priceFace, badgeFace)
		// CTA row under the card: "Mua với Voucher" (when the shop runs a voucher)
		// then "Xem sản phẩm (n)" (when >1 product). Static mirrors of the feed's
		// tappable buttons, which stay live Flutter UI over the raw clip in-app —
		// same brand-orange gradient pills as the in-app chips.
		ctaY := cardTop + cardH + 12*scale
		cx := margin
		if in.ShopHasVoucher {
			cx += drawPill(dc, "Mua với Voucher", cx, ctaY, scale, pillFace) + 10*scale
		}
		if len(in.Products) > 1 {
			drawPill(dc, fmt.Sprintf("Xem sản phẩm (%d)", len(in.Products)), cx, ctaY, scale, pillFace)
		}
	}

	// ── Action rail (right edge) ──
	drawActionRail(ctx, dc, in, W, H, scale, countFace)

	// ── Handle / caption / hashtags (bottom-left) ──
	y := H * 0.82
	if h := strings.TrimSpace(in.Handle); h != "" {
		dc.SetFontFace(handleFace)
		drawShadowString(dc, h, margin, y)
		y += 44 * scale
	}
	if caption := truncateRunes(strings.TrimSpace(in.Caption), 120); caption != "" {
		dc.SetFontFace(captionFace)
		drawShadowWrapped(dc, caption, margin, y, blockW, scale)
		// Advance by the caption's ACTUAL wrapped height (measured at blockW)
		// so the hashtag line below never overlaps it. The old fixed 1–2 line
		// estimate undercounted on a narrow block and stacked the tags on top
		// of the caption's last line.
		_, capH := dc.MeasureMultilineString(strings.Join(dc.WordWrap(caption, blockW), "\n"), 1.2)
		y += capH + 8*scale
	}
	// Drop hashtags already written inline in the caption so they don't render
	// twice (creators often end the caption with the same #tag).
	if tags := hashtagsNotInCaption(in.Caption, in.Hashtags); len(tags) > 0 {
		dc.SetFontFace(tagFace)
		drawShadowString(dc, truncateRunes("#"+strings.Join(tags, " #"), 60), margin, y)
	}

	// ── Watermark (bottom-right) ──
	wm := in.WatermarkText
	if wm == "" {
		wm = "TROPIA"
	}
	dc.SetFontFace(wmFace)
	tw, _ := dc.MeasureString(wm)
	// Translucent white, premultiplied (R=G=B=A) so it stays a valid colour —
	// see the voucher-pill note above re: Go's alpha-premultiplied color.RGBA.
	drawShadowStringColor(dc, wm, W-tw-margin, H-margin, color.RGBA{200, 200, 200, 200})

	return savePNG(dc, outPath)
}

// drawFeedProductCard draws one white rounded card (image + name + price) and
// returns its height. Mirrors the feed's product card.
func drawFeedProductCard(dc *gg.Context, p Product, x, y, w, scale float64, nameFace, priceFace, flashFace font.Face) float64 {
	cardH := 100 * scale
	imgSize := 76 * scale
	pad := 12 * scale

	// Soft drop-shadow so the white card lifts off a bright clip (mirrors the
	// in-app card's BoxShadow).
	drawSoftShadow(dc, x, y, w, cardH, 14*scale, scale)

	// Card background.
	dc.SetRGB(1, 1, 1)
	dc.DrawRoundedRectangle(x, y, w, cardH, 14*scale)
	dc.Fill()

	// Product image (or grey placeholder).
	imgX, imgY := x+pad, y+(cardH-imgSize)/2
	dc.DrawRoundedRectangle(imgX, imgY, imgSize, imgSize, 10*scale)
	dc.Clip()
	if img := fetchImage(context.Background(), p.ImageURL); img != nil {
		dc.DrawImageAnchored(scaleToFill(img, int(imgSize), int(imgSize)), int(imgX+imgSize/2), int(imgY+imgSize/2), 0.5, 0.5)
	} else {
		dc.SetRGB255(230, 230, 230)
		dc.DrawRectangle(imgX, imgY, imgSize, imgSize)
		dc.Fill()
	}
	dc.ResetClip()

	// Flash-sale tag across the TOP of the card image (Shopee-style), so it never
	// reaches into the product name on the right. Static — the live countdown
	// stays Flutter UI in-app; a frozen timer in a baked clip would lie, so we
	// only mark THAT a flash sale is on, not how long is left.
	if p.Flash && flashFace != nil {
		bh := 24 * scale
		dc.SetRGB255(255, 70, 30)
		dc.DrawRoundedRectangle(imgX, imgY, imgSize, bh, 7*scale)
		dc.Fill()
		dc.SetFontFace(flashFace)
		dc.SetRGB(1, 1, 1)
		dc.DrawStringAnchored("FLASH SALE", imgX+imgSize/2, imgY+bh/2, 0.5, 0.42)
	}

	textX := imgX + imgSize + pad
	textW := x + w - textX - pad

	// Name (black, wrapped to one line region near the top).
	dc.SetFontFace(nameFace)
	dc.SetRGB(0.08, 0.08, 0.08)
	dc.DrawStringWrapped(p.Name, textX, y+pad, 0, 0, textW, 1.1, gg.AlignLeft)

	// Price (red, bottom-aligned).
	dc.SetFontFace(priceFace)
	dc.SetRGB255(229, 57, 53)
	dc.DrawString(FormatVND(p.SalePrice), textX, y+cardH-pad)

	return cardH
}

// Brand-orange gradient for the baked CTA / voucher pills, matching the Flutter
// feed chips (secondaryLight #FF8A65 → secondaryDark #E64A19). A=255 keeps the
// colours valid under Go's alpha-premultiplied color.RGBA.
var (
	pillOrangeTop = color.RGBA{255, 138, 101, 255}
	pillOrangeBot = color.RGBA{230, 74, 25, 255}
)

// drawPill draws one rounded brand-orange gradient label pill at (x,y) with a
// soft drop-shadow, and returns its width so a caller can lay several out
// left-to-right with its own spacing.
func drawPill(dc *gg.Context, label string, x, y, scale float64, face font.Face) float64 {
	if face == nil {
		return 0
	}
	dc.SetFontFace(face)
	h := 44 * scale
	padX := 16 * scale
	tw, _ := dc.MeasureString(label)
	pw := tw + padX*2

	drawSoftShadow(dc, x, y, pw, h, h/2, scale)

	grad := gg.NewLinearGradient(x, y, x, y+h)
	grad.AddColorStop(0, pillOrangeTop)
	grad.AddColorStop(1, pillOrangeBot)
	dc.SetFillStyle(grad)
	dc.DrawRoundedRectangle(x, y, pw, h, h/2)
	dc.Fill()

	dc.SetRGB(1, 1, 1)
	dc.DrawStringAnchored(label, x+pw/2, y+h/2, 0.5, 0.4)
	return pw
}

// drawPillRow lays out one or more gradient pills left-to-right.
func drawPillRow(dc *gg.Context, labels []string, x, y, scale float64, face font.Face) {
	cx := x
	for _, label := range labels {
		cx += drawPill(dc, label, cx, y, scale, face) + 10*scale
	}
}

// drawSoftShadow fakes a blurred drop-shadow under a rounded rect by stacking a
// few translucent, progressively larger rounded rects offset slightly downward.
// gg has no Gaussian blur, so this is a cheap approximation that still reads as
// depth over a bright clip.
func drawSoftShadow(dc *gg.Context, x, y, w, h, r, scale float64) {
	for i := 0; i < 4; i++ {
		grow := float64(i) * 1.6 * scale
		dc.SetRGBA(0, 0, 0, 0.06)
		dc.DrawRoundedRectangle(x-grow, y-grow+4*scale, w+2*grow, h+2*grow, r+grow)
		dc.Fill()
	}
}

// ── Action rail ──────────────────────────────────────────────────────────────

// drawActionRail bakes a static copy of the feed's right-edge action rail:
// creator avatar (with a red follow "+"), then heart / comment / share glyphs,
// each with its snapshot count below. Icons are drawn white with a soft dark
// drop-shadow so they stay legible over a bright clip.
func drawActionRail(ctx context.Context, dc *gg.Context, in FeedOverlayInput, W, H, scale float64, countFace font.Face) {
	cx := W - 0.045*W - 30*scale // center x of the rail
	slot := 92 * scale           // vertical gap between icon slots
	bottomY := H * 0.74          // share icon (bottom of the stack) center
	isz := 38 * scale            // nominal glyph size
	shadow := color.RGBA{0, 0, 0, 110}

	// Avatar head + follow (+) at the top of the stack.
	drawRailAvatar(ctx, dc, in.AvatarURL, cx, bottomY-3*slot, 30*scale, scale)

	rows := []struct {
		y     float64
		kind  string
		count int
	}{
		{bottomY - 2*slot, "heart", in.LikeCount},
		{bottomY - 1*slot, "comment", in.CommentCount},
		{bottomY, "share", in.ShareCount},
	}
	for _, r := range rows {
		dc.SetColor(shadow)
		drawRailGlyph(dc, r.kind, cx+2*scale, r.y+2*scale, isz)
		dc.SetRGB(1, 1, 1)
		drawRailGlyph(dc, r.kind, cx, r.y, isz)
		if label := compactCount(r.count); label != "" && countFace != nil {
			dc.SetFontFace(countFace)
			tw, _ := dc.MeasureString(label)
			drawShadowStringColor(dc, label, cx-tw/2, r.y+isz*0.95, color.RGBA{255, 255, 255, 255})
		}
	}
}

// drawRailGlyph dispatches to the per-icon vector drawer using the current
// fill/stroke colour (so the caller can paint a shadow pass then a white pass).
func drawRailGlyph(dc *gg.Context, kind string, cx, cy, s float64) {
	switch kind {
	case "heart":
		drawHeart(dc, cx, cy, s)
	case "comment":
		drawCommentIcon(dc, cx, cy, s)
	case "share":
		drawShareIcon(dc, cx, cy, s)
	}
}

// drawRailAvatar draws the round creator/shop avatar (or a grey disc on miss)
// with a thin white ring and a red "+" follow badge centred on its bottom edge.
func drawRailAvatar(ctx context.Context, dc *gg.Context, url string, cx, cy, r, scale float64) {
	dc.SetRGB(1, 1, 1) // white ring
	dc.DrawCircle(cx, cy, r+2.5*scale)
	dc.Fill()

	dc.DrawCircle(cx, cy, r)
	dc.Clip()
	if img := fetchImage(ctx, url); img != nil {
		dc.DrawImageAnchored(scaleToFill(img, int(r*2), int(r*2)), int(cx), int(cy), 0.5, 0.5)
	} else {
		dc.SetRGB255(190, 190, 190)
		dc.DrawCircle(cx, cy, r)
		dc.Fill()
	}
	dc.ResetClip()

	bcy := cy + r // follow (+) badge on the bottom edge
	dc.SetRGB255(255, 77, 79)
	dc.DrawCircle(cx, bcy, 11*scale)
	dc.Fill()
	dc.SetRGB(1, 1, 1)
	dc.SetLineWidth(2.4 * scale)
	dc.DrawLine(cx-5*scale, bcy, cx+5*scale, bcy)
	dc.DrawLine(cx, bcy-5*scale, cx, bcy+5*scale)
	dc.Stroke()
}

// drawHeart fills a heart (two top lobes + a bottom triangle) centred at (cx,cy)
// roughly s tall, using the current colour.
func drawHeart(dc *gg.Context, cx, cy, s float64) {
	r := s * 0.30
	dc.DrawCircle(cx-r, cy-r*0.5, r)
	dc.DrawCircle(cx+r, cy-r*0.5, r)
	dc.Fill()
	dc.MoveTo(cx-2*r, cy-r*0.2)
	dc.LineTo(cx+2*r, cy-r*0.2)
	dc.LineTo(cx, cy+1.7*r)
	dc.ClosePath()
	dc.Fill()
}

// drawCommentIcon fills a rounded speech bubble with a small bottom-left tail.
func drawCommentIcon(dc *gg.Context, cx, cy, s float64) {
	w, h := s*1.15, s*0.95
	dc.DrawRoundedRectangle(cx-w/2, cy-h/2-s*0.08, w, h, s*0.28)
	dc.Fill()
	dc.MoveTo(cx-w*0.18, cy+h*0.34)
	dc.LineTo(cx-w*0.42, cy+h*0.62)
	dc.LineTo(cx-w*0.02, cy+h*0.34)
	dc.ClosePath()
	dc.Fill()
}

// drawShareIcon strokes a curved shaft + a filled arrowhead (a "↪" send mark).
func drawShareIcon(dc *gg.Context, cx, cy, s float64) {
	dc.SetLineWidth(s * 0.16)
	dc.MoveTo(cx-s*0.55, cy+s*0.35)
	dc.QuadraticTo(cx-s*0.1, cy-s*0.45, cx+s*0.42, cy-s*0.3)
	dc.Stroke()
	dc.MoveTo(cx+s*0.10, cy-s*0.55)
	dc.LineTo(cx+s*0.55, cy-s*0.28)
	dc.LineTo(cx+s*0.10, cy-s*0.02)
	dc.ClosePath()
	dc.Fill()
}

// compactCount formats a counter the way the feed rail does: "" for 0 (icon
// only — never a stale number), the raw value under 1 000, else "1,2K" / "3,4M"
// (comma decimal, matching Vietnamese).
func compactCount(n int) string {
	if n <= 0 {
		return ""
	}
	if n < 1000 {
		return strconv.Itoa(n)
	}
	v, suffix := float64(n)/1000, "K"
	if n >= 1_000_000 {
		v, suffix = float64(n)/1_000_000, "M"
	}
	s := strings.Replace(strings.TrimSuffix(strconv.FormatFloat(v, 'f', 1, 64), ".0"), ".", ",", 1)
	return s + suffix
}

// drawShadowString draws white text with a soft dark drop-shadow for legibility.
func drawShadowString(dc *gg.Context, s string, x, y float64) {
	drawShadowStringColor(dc, s, x, y, color.RGBA{255, 255, 255, 255})
}

func drawShadowStringColor(dc *gg.Context, s string, x, y float64, fg color.RGBA) {
	dc.SetRGBA(0, 0, 0, 0.55)
	dc.DrawString(s, x+2, y+2)
	dc.SetColor(fg)
	dc.DrawString(s, x, y)
}

func drawShadowWrapped(dc *gg.Context, s string, x, y, w, _ float64) {
	dc.SetRGBA(0, 0, 0, 0.55)
	dc.DrawStringWrapped(s, x+2, y+2, 0, 0, w, 1.2, gg.AlignLeft)
	dc.SetRGB(1, 1, 1)
	dc.DrawStringWrapped(s, x, y, 0, 0, w, 1.2, gg.AlignLeft)
}

// hashtagsNotInCaption returns the tags whose "#tag" doesn't already appear in
// caption (case-insensitive), so the baked hashtag line doesn't repeat what the
// caption already shows inline (creators often end the caption with the tag).
func hashtagsNotInCaption(caption string, tags []string) []string {
	capLower := strings.ToLower(caption)
	out := make([]string, 0, len(tags))
	for _, t := range tags {
		if strings.Contains(capLower, "#"+strings.ToLower(t)) {
			continue
		}
		out = append(out, t)
	}
	return out
}

// ── FFmpeg compositing ──────────────────────────────────────────────────────

// FeedBakeInput points BakeFeedOverlay at the raw clip + the overlay PNG.
type FeedBakeInput struct {
	SrcPath    string // local path to the raw mp4 (downloaded from R2)
	OverlayPNG string // local path to the RenderFeedOverlay PNG
	WorkDir    string // scratch dir; caller cleans up
	Logger     *slog.Logger
}

// BakeFeedOverlay composites the overlay PNG over the raw clip in a single
// FFmpeg pass and returns the path to the baked MP4. scale2ref resizes the PNG
// to the clip's actual resolution first, so a 1080×1920 render still lines up
// on a 720×1280 (or any) source. The filter graph references only stream
// labels (no file paths), so it's free of the Windows ':' parser pitfall that
// forces the replay bake to cd into its work dir.
func BakeFeedOverlay(ctx context.Context, in FeedBakeInput) (string, error) {
	if in.Logger == nil {
		in.Logger = slog.Default()
	}
	if err := os.MkdirAll(in.WorkDir, 0o755); err != nil {
		return "", fmt.Errorf("mkdir work: %w", err)
	}
	src, _ := filepath.Abs(in.SrcPath)
	png, _ := filepath.Abs(in.OverlayPNG)
	out := filepath.Join(in.WorkDir, "overlay.mp4")

	args := []string{
		"-y",
		"-i", src,
		"-i", png,
		"-filter_complex", "[1:v][0:v]scale2ref[ovl][base];[base][ovl]overlay=0:0[vout]",
		"-map", "[vout]",
		"-map", "0:a?",
		"-c:v", "libx264",
		"-preset", "veryfast",
		"-crf", "23",
		"-c:a", "copy",
		"-movflags", "+faststart",
		out,
	}
	cmd := exec.CommandContext(ctx, "ffmpeg", args...)
	start := time.Now()
	o, err := cmd.CombinedOutput()
	if err != nil {
		tail := string(o)
		if len(tail) > 1200 {
			tail = "..." + tail[len(tail)-1200:]
		}
		return "", fmt.Errorf("ffmpeg overlay bake failed: %w — %s", err, tail)
	}
	in.Logger.Info("feed overlay bake: ffmpeg done",
		"out", out, "dur", time.Since(start).Truncate(time.Millisecond))
	return out, nil
}
