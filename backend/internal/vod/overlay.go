package vod

import (
	"context"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/fogleman/gg"
	"github.com/golang/freetype/truetype"
	"golang.org/x/image/font"

	"github.com/tropia/backend/internal/safefetch"
)

// Overlay PNGs are rendered at this DPR-equivalent size and placed on
// the video via FFmpeg's `overlay` filter. We don't need to match the
// video's full resolution — a 600px-wide PNG looks fine on a 1080p
// vertical stream and keeps the encode cheap.
const (
	pinBannerW    = 540
	pinBannerH    = 88
	couponW       = 360
	couponH       = 56
	botChipW      = 140
	botChipH      = 44
	giftW         = 380
	giftH         = 72
	defaultFontPx = 22

	// giftLaneStep is the vertical gap (px) between two stacked gift
	// banners. Gifts live in the RIGHT column (see overlayExpr), which is
	// free of the left-side products and the bottom chat, so the stack can
	// grow downward through most of the frame. giftMaxLane caps it before
	// the bottom chat band: on the smallest source in use (720×1280, chat
	// top ≈755px) base 280 + 4*step(80) + giftH(72) = 672 < 755 still
	// clears. Bursts beyond that reuse the last lane (overlap each other)
	// rather than running into the chat.
	giftLaneStep = giftH + 8
	giftMaxLane  = 4
)

// fontPath defaults to the Windows Arial TTF (which supports Vietnamese
// diacritics fine). Override via VOD_FONT env if running on Linux —
// e.g. /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf.
func fontPath() string {
	if p := os.Getenv("VOD_FONT"); p != "" {
		return p
	}
	if _, err := os.Stat(`C:\Windows\Fonts\arialbd.ttf`); err == nil {
		return `C:\Windows\Fonts\arialbd.ttf`
	}
	// Linux fallback — common location in Debian/Ubuntu base images.
	for _, p := range []string{
		"/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
		"/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
	} {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

// loadFace loads a TTF font at the requested point size. Falls back
// to gg's built-in Go font if no system font is found — that font
// doesn't render Vietnamese diacritics, so log a warning.
func loadFace(points float64) (font.Face, error) {
	path := fontPath()
	if path == "" {
		return nil, fmt.Errorf("no system font found; set VOD_FONT")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	f, err := truetype.Parse(data)
	if err != nil {
		return nil, err
	}
	return truetype.NewFace(f, &truetype.Options{Size: points, DPI: 72, Hinting: font.HintingFull}), nil
}

// ── Pin banner ──────────────────────────────────────────────────────

type PinAsset struct {
	Path    string  // PNG path written to workDir
	StartMs int64   // when to show (inclusive)
	EndMs   int64   // when to hide
}

// RenderPinBanner draws a white rounded card with a red
// "ĐANG GIỚI THIỆU" badge + [product image] + [product name] + [price
// in red]. Mirrors the Flutter _PinnedSpotlight widget. If imageURL is
// non-empty, the image is fetched (with short timeout) and pasted into
// the card; on fetch error a grey placeholder is drawn instead.
func RenderPinBanner(ctx context.Context, name string, price float64, imageURL string, outPath string) error {
	dc := gg.NewContext(pinBannerW, pinBannerH)

	// White rounded background with soft shadow.
	dc.SetRGB(1, 1, 1)
	dc.DrawRoundedRectangle(0, 0, float64(pinBannerW), float64(pinBannerH), 14)
	dc.Fill()

	// Product image (72×72) — or placeholder.
	imgX, imgY := 8.0, 8.0
	imgSize := 72.0
	dc.DrawRoundedRectangle(imgX, imgY, imgSize, imgSize, 10)
	dc.Clip()
	if img := fetchImage(ctx, imageURL); img != nil {
		dc.DrawImageAnchored(scaleToFill(img, int(imgSize), int(imgSize)), int(imgX+imgSize/2), int(imgY+imgSize/2), 0.5, 0.5)
	} else {
		dc.SetRGB255(230, 230, 230)
		dc.DrawRectangle(imgX, imgY, imgSize, imgSize)
		dc.Fill()
	}
	dc.ResetClip()

	textX := imgX + imgSize + 12

	// Badge "ĐANG GIỚI THIỆU" — red pill at top of right column, mirrors
	// the pulsing badge in Flutter _PinnedSpotlight (static here — no
	// animation in a baked PNG, the colour alone reads "live highlight").
	badgeFace, err := loadFace(13)
	if err != nil {
		return err
	}
	dc.SetFontFace(badgeFace)
	badgeText := "ĐANG GIỚI THIỆU"
	badgeTextW, badgeTextH := dc.MeasureString(badgeText)
	badgePadX, badgePadY := 7.0, 3.0
	badgeW := badgeTextW + badgePadX*2
	badgeH := badgeTextH + badgePadY*2
	badgeY := 8.0
	dc.SetRGB255(255, 77, 79) // #FF4D4F
	dc.DrawRoundedRectangle(textX, badgeY, badgeW, badgeH, 4)
	dc.Fill()
	dc.SetRGB(1, 1, 1)
	dc.DrawString(badgeText, textX+badgePadX, badgeY+badgePadY+badgeTextH-2)

	// Name (black, bold) — below badge.
	face, err := loadFace(20)
	if err != nil {
		return err
	}
	dc.SetFontFace(face)
	dc.SetRGB(0.08, 0.08, 0.08)
	dc.DrawStringWrapped(name, textX, badgeY+badgeH+6, 0, 0, float64(pinBannerW)-imgSize-32, 1.15, gg.AlignLeft)

	// Price (red, larger) — bottom-aligned in the card.
	priceFace, err := loadFace(22)
	if err != nil {
		return err
	}
	dc.SetFontFace(priceFace)
	dc.SetRGB255(229, 57, 53) // red 600
	dc.DrawString(FormatVND(price), textX, float64(pinBannerH)-10)

	return savePNG(dc, outPath)
}

// ── Coupon banner ───────────────────────────────────────────────────

// RenderCouponBanner draws an orange-red gradient pill with the
// discount label + a small code badge. Matches the Flutter
// _CouponBannerView widget.
func RenderCouponBanner(discountType, code string, value float64, outPath string) error {
	dc := gg.NewContext(couponW, couponH)

	// Manual vertical gradient: orange top → red bottom. gg's gradient
	// API works on shapes via SetFillStyle; for a simple banner we
	// fake it with two rectangles + soft blend isn't worth the code.
	// Use solid red-orange instead.
	dc.SetRGB255(255, 70, 30)
	dc.DrawRoundedRectangle(0, 0, float64(couponW), float64(couponH), 20)
	dc.Fill()

	// Discount label.
	face, err := loadFace(20)
	if err != nil {
		return err
	}
	dc.SetFontFace(face)
	dc.SetRGB(1, 1, 1)

	label := fmt.Sprintf("Giảm %.0f%%", value)
	if discountType != "percent" {
		label = "Giảm " + FormatVND(value)
	}
	dc.DrawString(label, 20, 35)

	// Code badge — white-on-translucent on the right side.
	smallFace, err := loadFace(15)
	if err != nil {
		return err
	}
	dc.SetFontFace(smallFace)
	textW, _ := dc.MeasureString(code)
	badgeW := textW + 16
	badgeX := float64(couponW) - badgeW - 16
	badgeY := 14.0
	dc.SetRGBA(1, 1, 1, 0.25)
	dc.DrawRoundedRectangle(badgeX, badgeY, badgeW, 28, 6)
	dc.Fill()
	dc.SetRGB(1, 1, 1)
	dc.DrawString(code, badgeX+8, badgeY+19)

	return savePNG(dc, outPath)
}

// RenderGiftBanner draws a pink rounded banner with a left accent disc and
// two lines: the sender name + "Tặng {n}x {gift}". Burned into the VOD so
// gifts show as a proper banner in replay (not just a chat subtitle line).
func RenderGiftBanner(sender, giftName string, qty int, outPath string) error {
	dc := gg.NewContext(giftW, giftH)

	// Banner body — magenta/pink rounded card.
	dc.SetRGB255(233, 30, 99)
	dc.DrawRoundedRectangle(0, 0, float64(giftW), float64(giftH), 18)
	dc.Fill()

	// Left accent disc.
	dc.SetRGBA(1, 1, 1, 0.22)
	dc.DrawCircle(40, float64(giftH)/2, 24)
	dc.Fill()
	// A small gift "box" mark inside the disc (two strokes — emoji fonts
	// aren't guaranteed, so draw a simple glyph).
	dc.SetRGB(1, 1, 1)
	dc.SetLineWidth(3)
	dc.DrawRectangle(28, float64(giftH)/2-6, 24, 16)
	dc.Stroke()
	dc.DrawLine(40, float64(giftH)/2-6, 40, float64(giftH)/2+10)
	dc.Stroke()

	if sender == "" {
		sender = "Người xem"
	}
	if giftName == "" {
		giftName = "Quà"
	}
	if qty <= 0 {
		qty = 1
	}

	// Sender (top line).
	face, err := loadFace(20)
	if err != nil {
		return err
	}
	dc.SetFontFace(face)
	dc.SetRGB(1, 1, 1)
	dc.DrawString(truncateRunes(sender, 22), 80, 30)

	// Gift line (bottom).
	small, err := loadFace(16)
	if err != nil {
		return err
	}
	dc.SetFontFace(small)
	dc.SetRGB255(255, 235, 130) // soft amber
	dc.DrawString(fmt.Sprintf("Tặng %dx %s", qty, truncateRunes(giftName, 24)), 80, 56)

	return savePNG(dc, outPath)
}

// truncateRunes shortens s to at most n runes (so Vietnamese diacritics
// aren't cut mid-character), appending an ellipsis when trimmed.
func truncateRunes(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "…"
}

// ── Product list (carousel mirror) ──────────────────────────────────

const (
	prodCardW = 280
	prodCardH = 76
	prodGap   = 8
)

// Product is the minimal shape RenderProductList needs.
// Mirrors live.SessionProduct without dragging in the dep at the
// package boundary.
type Product struct {
	Name      string
	SalePrice float64
	ImageURL  string
	// Flash marks the product as currently in a flash sale at bake time. Only
	// the feed overlay uses it (to stamp a static "FLASH SALE" badge on the
	// card); the replay's RenderProductList ignores it.
	Flash bool
}

// RenderProductList draws a vertical stack of mini cards (image +
// name + price) — one card per product — into a single PNG. Mirrors
// the left-edge product carousel of the live host screen so VOD
// viewers see the same products the host had on the cart shelf.
func RenderProductList(ctx context.Context, products []Product, outPath string) error {
	if len(products) == 0 {
		return fmt.Errorf("no products")
	}
	w := prodCardW
	h := len(products)*prodCardH + (len(products)-1)*prodGap
	dc := gg.NewContext(w, h)

	face, err := loadFace(15)
	if err != nil {
		return err
	}
	priceFace, err := loadFace(17)
	if err != nil {
		return err
	}

	for i, p := range products {
		y := float64(i * (prodCardH + prodGap))

		// White card with shadow.
		dc.SetRGB(1, 1, 1)
		dc.DrawRoundedRectangle(0, y, float64(prodCardW), float64(prodCardH), 10)
		dc.Fill()

		// Image 60x60 with rounded corners.
		imgX, imgY := 8.0, y+8.0
		imgSize := 60.0
		dc.DrawRoundedRectangle(imgX, imgY, imgSize, imgSize, 8)
		dc.Clip()
		if img := fetchImage(ctx, p.ImageURL); img != nil {
			dc.DrawImageAnchored(scaleToFill(img, int(imgSize), int(imgSize)), int(imgX+imgSize/2), int(imgY+imgSize/2), 0.5, 0.5)
		} else {
			dc.SetRGB255(230, 230, 230)
			dc.DrawRectangle(imgX, imgY, imgSize, imgSize)
			dc.Fill()
		}
		dc.ResetClip()

		// Name (top, black).
		dc.SetFontFace(face)
		dc.SetRGB(0.08, 0.08, 0.08)
		dc.DrawStringWrapped(p.Name, imgX+imgSize+10, y+10, 0, 0, float64(prodCardW)-imgSize-24, 1.15, gg.AlignLeft)

		// Price (bottom, red).
		dc.SetFontFace(priceFace)
		dc.SetRGB255(229, 57, 53)
		dc.DrawString(FormatVND(p.SalePrice), imgX+imgSize+10, y+float64(prodCardH)-16)
	}

	return savePNG(dc, outPath)
}

// ── Bot chip ────────────────────────────────────────────────────────

// RenderBotChip draws a green pill labelled "Bot ON" — mirrors the
// chip in the live host view (top-right of LiveStreamScreen).
func RenderBotChip(outPath string) error {
	dc := gg.NewContext(botChipW, botChipH)

	dc.SetRGB255(67, 200, 95) // greenAccent-ish
	dc.DrawRoundedRectangle(0, 0, float64(botChipW), float64(botChipH), 18)
	dc.Fill()

	face, err := loadFace(18)
	if err != nil {
		return err
	}
	dc.SetFontFace(face)
	dc.SetRGB(0, 0, 0)
	dc.DrawString("Bot ON", 24, 28)

	// Small white circle as "indicator dot" on the left.
	dc.SetRGB(1, 1, 1)
	dc.DrawCircle(13, 22, 4)
	dc.Fill()

	return savePNG(dc, outPath)
}

// ── Helpers ─────────────────────────────────────────────────────────

func savePNG(dc *gg.Context, path string) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return png.Encode(f, dc.Image())
}

// fetchImage downloads + decodes a JPEG/PNG with a 5s timeout. Returns
// nil on any failure (caller falls back to a placeholder).
//
// url is untrusted (a seller-supplied product image URL, stored verbatim),
// so the fetch goes through the SSRF guard: a URL that resolves to an
// internal/metadata address is refused at connect time, and we just fall
// back to the placeholder.
func fetchImage(ctx context.Context, url string) image.Image {
	if url == "" {
		return nil
	}
	cctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(cctx, http.MethodGet, url, nil)
	if err != nil {
		return nil
	}
	resp, err := safefetch.Default.Do(req)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return nil
	}
	// Try JPEG first (most product images), then PNG.
	body, err := io.ReadAll(io.LimitReader(resp.Body, 8*1024*1024))
	if err != nil {
		return nil
	}
	if img, err := jpeg.Decode(byteReader(body)); err == nil {
		return img
	}
	if img, err := png.Decode(byteReader(body)); err == nil {
		return img
	}
	// Fall back to generic decoder.
	if img, _, err := image.Decode(byteReader(body)); err == nil {
		return img
	}
	return nil
}

type bytesReader struct {
	b []byte
	i int
}

func byteReader(b []byte) *bytesReader { return &bytesReader{b: b} }
func (r *bytesReader) Read(p []byte) (int, error) {
	if r.i >= len(r.b) {
		return 0, io.EOF
	}
	n := copy(p, r.b[r.i:])
	r.i += n
	return n, nil
}

// scaleToFill resizes an image so it fully covers a w×h box (may crop).
// Returns a center-cropped image of exactly w×h. Uses nearest-neighbor
// sampling via the std-lib draw.NearestNeighbor (good enough for 72px
// thumbnails).
func scaleToFill(src image.Image, w, h int) image.Image {
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	sb := src.Bounds()
	sw, sh := sb.Dx(), sb.Dy()
	if sw == 0 || sh == 0 {
		return dst
	}
	// Pick the larger scale so we fill the box (cover, not contain).
	scale := float64(w) / float64(sw)
	if s := float64(h) / float64(sh); s > scale {
		scale = s
	}
	dw := int(float64(sw) * scale)
	dh := int(float64(sh) * scale)
	// Offset to center-crop.
	ox := (dw - w) / 2
	oy := (dh - h) / 2
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			sx := int(float64(x+ox) / scale)
			sy := int(float64(y+oy) / scale)
			if sx >= sw {
				sx = sw - 1
			}
			if sy >= sh {
				sy = sh - 1
			}
			dst.Set(x, y, src.At(sb.Min.X+sx, sb.Min.Y+sy))
		}
	}
	return dst
}

// ── Build overlay assets from timeline ──────────────────────────────

// OverlayAsset is one PNG + the time window it should appear on screen.
// Position is computed in BuildFFmpegFilter (depends on overlay type).
type OverlayAsset struct {
	Path    string
	Type    string // "pin" | "coupon" | "bot" | "gift"
	StartMs int64
	EndMs   int64

	// Lane is a vertical stacking slot for overlays that can appear
	// concurrently at the same base position. Only gifts use it today:
	// two gifts whose 5s windows overlap get distinct lanes so they
	// stack instead of drawing on top of each other. 0 = base position.
	Lane int
}

// PrepareOverlays walks live_events, renders the appropriate PNG into
// workDir, and returns the assets with their time windows. Returns
// the list in chronological order so the FFmpeg filter graph chain
// reads naturally.
//
// `endMs` is the duration of the video — used to clamp the visible
// window of overlays that should "stick" to the end (e.g. bot chip
// once enabled stays on until the stream ends).
func PrepareOverlays(ctx context.Context, events []LiveEventLite, workDir string, endMs int64) ([]OverlayAsset, error) {
	var assets []OverlayAsset

	// Coupons: each event → a banner shown for 6s.
	for i, e := range events {
		if e.Type != "coupon_publish" {
			continue
		}
		path := filepath.Join(workDir, fmt.Sprintf("coupon_%d.png", i))
		if err := RenderCouponBanner(e.CouponType, e.CouponCode, e.CouponValue, path); err != nil {
			return nil, fmt.Errorf("render coupon: %w", err)
		}
		end := e.StartMs + 6000
		if end > endMs {
			end = endMs
		}
		assets = append(assets, OverlayAsset{Path: path, Type: "coupon", StartMs: e.StartMs, EndMs: end})
	}

	// Gifts: each event → a banner shown for 5s. Gifts arrive in bursts
	// during a live, and every banner renders at the same center spot, so
	// concurrent ones would stack on top of each other and become an
	// unreadable smear. Assign each gift the lowest vertical lane whose
	// previous occupant has already faded out (greedy interval colouring);
	// bake.go offsets each lane upward, away from the bottom chat band.
	// `giftLaneEnds[l]` holds the EndMs of the gift currently in lane l.
	var giftLaneEnds []int64
	for i, e := range events {
		if e.Type != "gift" {
			continue
		}
		path := filepath.Join(workDir, fmt.Sprintf("gift_%d.png", i))
		if err := RenderGiftBanner(e.GiftSender, e.GiftName, e.GiftQty, path); err != nil {
			return nil, fmt.Errorf("render gift: %w", err)
		}
		end := e.StartMs + 5000
		if end > endMs {
			end = endMs
		}
		lane := -1
		for l, le := range giftLaneEnds {
			if e.StartMs >= le { // lane free again by the time this gift starts
				lane = l
				giftLaneEnds[l] = end
				break
			}
		}
		if lane == -1 {
			lane = len(giftLaneEnds)
			giftLaneEnds = append(giftLaneEnds, end)
		}
		if lane > giftMaxLane { // cap so a gift storm never marches off the top
			lane = giftMaxLane
		}
		assets = append(assets, OverlayAsset{Path: path, Type: "gift", StartMs: e.StartMs, EndMs: end, Lane: lane})
	}

	// Pins: pair up product_pin / product_unpin into spans. If a pin
	// has no unpin (host ended without unpinning), span runs to endMs.
	var openPin *LiveEventLite
	pinIdx := 0
	for i := range events {
		e := events[i]
		switch e.Type {
		case "product_pin":
			openPin = &events[i]
		case "product_unpin":
			if openPin != nil {
				path := filepath.Join(workDir, fmt.Sprintf("pin_%d.png", pinIdx))
				pinIdx++
				if err := RenderPinBanner(ctx, openPin.PinName, openPin.PinPrice, openPin.PinImageURL, path); err != nil {
					return nil, fmt.Errorf("render pin: %w", err)
				}
				assets = append(assets, OverlayAsset{Path: path, Type: "pin", StartMs: openPin.StartMs, EndMs: e.StartMs})
				openPin = nil
			}
		}
	}
	if openPin != nil {
		path := filepath.Join(workDir, fmt.Sprintf("pin_%d.png", pinIdx))
		if err := RenderPinBanner(ctx, openPin.PinName, openPin.PinPrice, openPin.PinImageURL, path); err != nil {
			return nil, fmt.Errorf("render pin: %w", err)
		}
		assets = append(assets, OverlayAsset{Path: path, Type: "pin", StartMs: openPin.StartMs, EndMs: endMs})
	}

	// Bot chip: track on/off state. Show chip during every "on" span.
	var on bool
	var onStart int64
	for _, e := range events {
		if e.Type != "bot_toggle" {
			continue
		}
		if e.BotEnabled && !on {
			on = true
			onStart = e.StartMs
		} else if !e.BotEnabled && on {
			on = false
			path := filepath.Join(workDir, "bot_chip.png")
			if _, err := os.Stat(path); err != nil {
				if err := RenderBotChip(path); err != nil {
					return nil, err
				}
			}
			assets = append(assets, OverlayAsset{Path: path, Type: "bot", StartMs: onStart, EndMs: e.StartMs})
		}
	}
	if on {
		path := filepath.Join(workDir, "bot_chip.png")
		if _, err := os.Stat(path); err != nil {
			if err := RenderBotChip(path); err != nil {
				return nil, err
			}
		}
		assets = append(assets, OverlayAsset{Path: path, Type: "bot", StartMs: onStart, EndMs: endMs})
	}

	return assets, nil
}

// LiveEventLite is a parsed, type-specific view of one live_events row.
// PrepareOverlays uses these instead of working with raw JSON payload
// at render time — payload parsing happens once at the caller.
type LiveEventLite struct {
	Type    string
	StartMs int64

	// product_pin fields
	PinName     string
	PinPrice    float64
	PinImageURL string

	// coupon_publish fields
	CouponCode  string
	CouponType  string
	CouponValue float64

	// bot_toggle fields
	BotEnabled bool

	// gift fields
	GiftSender string
	GiftName   string
	GiftCode   string
	GiftQty    int
}

// Silence unused import warnings if color package isn't used elsewhere.
var _ = color.RGBA{}
