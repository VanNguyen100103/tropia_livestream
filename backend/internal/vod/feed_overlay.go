package vod

import (
	"context"
	"fmt"
	"image/color"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
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
}

// RenderFeedOverlay draws the static info layer into a single transparent PNG
// the size of the target video. BakeFeedOverlay then composites it over the
// raw clip in one FFmpeg pass. The layout mirrors the feed's bottom-left
// column: voucher pills → product card → "@handle" → caption → hashtags, with
// a bottom scrim for legibility and the watermark in the corner.
func RenderFeedOverlay(_ context.Context, in FeedOverlayInput, outPath string) error {
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

	// ── Voucher pills (above the product card) ──
	pillY := H * 0.55
	if len(in.CouponLabels) > 0 {
		drawPillRow(dc, in.CouponLabels, margin, pillY, scale, pillFace, color.RGBA{255, 70, 30, 235})
	}

	// ── Product card ──
	cardTop := H * 0.60
	if len(in.Products) > 0 {
		cardH := drawFeedProductCard(dc, in.Products[0], margin, cardTop, blockW, scale, nameFace, priceFace)
		if len(in.Products) > 1 {
			drawPillRow(dc, []string{fmt.Sprintf("Xem sản phẩm (%d)", len(in.Products))},
				margin, cardTop+cardH+12*scale, scale, pillFace, color.RGBA{0, 0, 0, 150})
		}
	}

	// ── Handle / caption / hashtags (bottom-left) ──
	y := H * 0.82
	if h := strings.TrimSpace(in.Handle); h != "" {
		dc.SetFontFace(handleFace)
		drawShadowString(dc, h, margin, y)
		y += 44 * scale
	}
	if caption := strings.TrimSpace(in.Caption); caption != "" {
		dc.SetFontFace(captionFace)
		drawShadowWrapped(dc, truncateRunes(caption, 120), margin, y, blockW, scale)
		// Reserve up to two lines for the caption.
		y += 38 * scale * minF(2, float64(lineCount(caption, 48)))
	}
	if len(in.Hashtags) > 0 {
		dc.SetFontFace(tagFace)
		tags := "#" + strings.Join(in.Hashtags, " #")
		drawShadowString(dc, truncateRunes(tags, 60), margin, y+6*scale)
	}

	// ── Watermark (bottom-right) ──
	wm := in.WatermarkText
	if wm == "" {
		wm = "TROPIA"
	}
	dc.SetFontFace(wmFace)
	tw, _ := dc.MeasureString(wm)
	drawShadowStringColor(dc, wm, W-tw-margin, H-margin, color.RGBA{255, 255, 255, 200})

	return savePNG(dc, outPath)
}

// drawFeedProductCard draws one white rounded card (image + name + price) and
// returns its height. Mirrors the feed's product card.
func drawFeedProductCard(dc *gg.Context, p Product, x, y, w, scale float64, nameFace, priceFace font.Face) float64 {
	cardH := 100 * scale
	imgSize := 76 * scale
	pad := 12 * scale

	// Card background.
	dc.SetRGBA(1, 1, 1, 0.96)
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

	textX := imgX + imgSize + pad
	textW := x + w - textX - pad

	// Name (black, wrapped to one line region near the top).
	dc.SetFontFace(nameFace)
	dc.SetRGB(0.08, 0.08, 0.08)
	dc.DrawStringWrapped(p.Name, textX, y+pad, 0, 0, textW, 1.1, gg.AlignLeft)

	// Price (red, bottom-aligned).
	dc.SetFontFace(priceFace)
	dc.SetRGB255(229, 57, 53)
	dc.DrawString(fmt.Sprintf("%.0fđ", p.SalePrice), textX, y+cardH-pad)

	return cardH
}

// drawPillRow lays out one or more rounded label pills left-to-right.
func drawPillRow(dc *gg.Context, labels []string, x, y, scale float64, face font.Face, bg color.RGBA) {
	if face == nil {
		return
	}
	dc.SetFontFace(face)
	cx := x
	h := 44 * scale
	padX := 16 * scale
	for _, label := range labels {
		tw, _ := dc.MeasureString(label)
		pw := tw + padX*2
		dc.SetColor(bg)
		dc.DrawRoundedRectangle(cx, y, pw, h, h/2)
		dc.Fill()
		dc.SetRGB(1, 1, 1)
		dc.DrawStringAnchored(label, cx+pw/2, y+h/2, 0.5, 0.4)
		cx += pw + 10*scale
	}
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

func minF(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}

// lineCount estimates how many wrapped lines a string spans at ~charsPerLine.
func lineCount(s string, charsPerLine int) int {
	n := (len([]rune(s)) + charsPerLine - 1) / charsPerLine
	if n < 1 {
		return 1
	}
	return n
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
