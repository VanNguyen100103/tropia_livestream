// Command worker is the background job runner for Tropia. It consumes
// Redis Streams events published by the api binary and reacts to them
// (mostly: send transactional email + post-process VOD recordings).
//
// Topics:
//   - user.registered         → welcome email
//   - auth.email_otp          → OTP email
//   - auth.password_reset     → password reset link email
//   - order.created           → order confirmation email
//   - payment.success         → payment receipt email
//   - order.cancelled         → cancellation email
//   - recording.created       → FFmpeg remux FLV→MP4 + upload to Cloudflare R2
//   - video.created           → bake static overlay onto the clip → upload copy
//
// Each handler runs in its own goroutine with its own consumer name so
// Redis Streams' consumer-group semantics give us at-least-once delivery
// + automatic retry on handler error (via PEL).
//
// Usage:
//
//	go run ./cmd/worker
//	make worker
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/google/uuid"
	"github.com/joho/godotenv"

	"github.com/tropia/backend/internal/config"
	"github.com/tropia/backend/internal/database"
	"github.com/tropia/backend/internal/events"
	"github.com/tropia/backend/internal/httpx"
	"github.com/tropia/backend/internal/live"
	"github.com/tropia/backend/internal/notify"
	"github.com/tropia/backend/internal/safefetch"
	"github.com/tropia/backend/internal/storage"
	"github.com/tropia/backend/internal/video"
	"github.com/tropia/backend/internal/vod"
)

const consumerName = "worker-1"

func main() {
	for _, f := range []string{".env.development", ".env"} {
		if _, err := os.Stat(f); err == nil {
			_ = godotenv.Load(f)
			log.Printf("loaded env from %s", f)
			break
		}
	}

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	logger := httpx.NewLogger(os.Getenv("NODE_ENV"))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	rds, err := database.NewRedis(ctx, cfg.RedisAddr, cfg.RedisPassword, cfg.RedisDB)
	if err != nil {
		log.Fatalf("redis: %v", err)
	}
	defer rds.Close()
	logger.Info("redis connected", "addr", cfg.RedisAddr)

	// Postgres — needed by the recording handler to update live_sessions.vod_*.
	db, err := database.NewPostgres(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("postgres: %v", err)
	}
	defer db.Close()
	logger.Info("postgres connected")

	sessRepo := live.NewSessionRepository(db)
	eventsRepo := live.NewEventRepository(db)
	videoRepo := video.NewRepository(db)

	// R2 (optional — if creds not set, recording handler will skip uploads).
	var r2 *storage.R2
	if cfg.R2AccountID != "" {
		r2, err = storage.NewR2(ctx, storage.R2Config{
			AccountID:       cfg.R2AccountID,
			AccessKeyID:     cfg.R2AccessKeyID,
			SecretAccessKey: cfg.R2SecretAccessKey,
			Bucket:          cfg.R2Bucket,
			PublicURL:       cfg.R2PublicURL,
		})
		if err != nil {
			logger.Warn("r2 init failed", "err", err)
		} else {
			logger.Info("r2 connected", "bucket", cfg.R2Bucket)
		}
	}

	bus := events.New(rds, logger)

	emailer := notify.NewEmail(notify.EmailConfig{
		Host:     getEnvOr("EMAIL_HOST", "smtp.gmail.com"),
		Port:     587,
		Username: os.Getenv("EMAIL_USERNAME"),
		Password: os.Getenv("EMAIL_PASSWORD"),
		FromName: getEnvOr("EMAIL_FROM_NAME", "Tropia"),
	})
	clientURL := getEnvOr("CLIENT_URL", "http://localhost:8080")

	dvrRoot := getEnvOr("DVR_HOST_PATH", "../infra/dvr")

	subs := []subscription{
		{topic: "user.registered", group: "notify-welcome", handler: handleWelcome(emailer, logger)},
		{topic: "auth.email_otp", group: "notify-otp", handler: handleOTP(emailer, logger)},
		{topic: "auth.password_reset", group: "notify-reset", handler: handlePasswordReset(emailer, logger, clientURL)},
		{topic: "order.created", group: "notify-order-created", handler: handleOrderCreated(emailer, logger)},
		{topic: "payment.success", group: "notify-payment-success", handler: handlePaymentSuccess(emailer, logger)},
		{topic: "order.cancelled", group: "notify-order-cancelled", handler: handleOrderCancelled(emailer, logger)},
		{topic: "recording.created", group: "vod-uploader", handler: handleRecording(r2, sessRepo, eventsRepo, dvrRoot, logger)},
		{topic: "video.created", group: "video-overlay", handler: handleVideoOverlay(r2, videoRepo, logger)},
	}

	var wg sync.WaitGroup
	for _, s := range subs {
		s := s
		wg.Add(1)
		go func() {
			defer wg.Done()
			logger.Info("subscribed", "topic", s.topic, "group", s.group)
			bus.Subscribe(ctx, s.topic, s.group, consumerName, s.handler)
		}()
	}

	// Periodic DVR sweep — removes orphaned .flv files left by failed
	// remuxes, crashed workers, or sessions cut mid-stream. Successful
	// uploads already delete their FLV; this is the safety net so the
	// host disk doesn't fill up over weeks of operation. 2h is long
	// enough that a slow ffmpeg can finish (typical: seconds; worst
	// case: minutes for a multi-hour stream), short enough that orphans
	// don't pile up.
	wg.Add(1)
	go func() {
		defer wg.Done()
		runDVRSweeper(ctx, dvrRoot, 30*time.Minute, 2*time.Hour, logger)
	}()

	// Max live-duration cap — force-end sessions running longer than
	// MAX_LIVE_DURATION (default 4h) so a forgotten/abandoned stream
	// doesn't stay "live" forever.
	maxLiveDuration := parseDurEnv("MAX_LIVE_DURATION", 2*time.Hour)
	wg.Add(1)
	go func() {
		defer wg.Done()
		runLiveDurationSweeper(ctx, sessRepo, 5*time.Minute, maxLiveDuration, logger)
	}()

	// VOD retention — delete recordings from R2 after RECORDING_RETENTION
	// (default 720h = 30 days), then mark the row 'expired'.
	recRetention := parseDurEnv("RECORDING_RETENTION", 30*24*time.Hour)
	wg.Add(1)
	go func() {
		defer wg.Done()
		runR2RetentionSweeper(ctx, sessRepo, r2, 6*time.Hour, recRetention, logger)
	}()

	logger.Info("worker running", "subscriptions", len(subs),
		"max_live_duration", maxLiveDuration, "recording_retention", recRetention)

	// Graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	<-sigCh
	logger.Info("shutting down worker")
	cancel()
	wg.Wait()
	logger.Info("bye")
	_ = slog.Default()
}

// ── Subscription wiring ─────────────────────────────────────────────────────

type subscription struct {
	topic   string
	group   string
	handler events.HandlerFunc
}

func decode[T any](data []byte) (T, error) {
	var v T
	err := json.Unmarshal(data, &v)
	return v, err
}

func getEnvOr(k, fallback string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return fallback
}

// ── Handlers ────────────────────────────────────────────────────────────────

type userEvent struct {
	UserID string `json:"user_id"`
	Email  string `json:"email"`
	Name   string `json:"name"`
}

type otpEvent struct {
	userEvent
	OTP string `json:"otp"`
}

type passwordResetEvent struct {
	userEvent
	ResetToken string `json:"reset_token"`
}

type orderLineItem struct {
	Name     string `json:"name"`
	Quantity int    `json:"quantity"`
	Price    int    `json:"price"`
}

type orderEvent struct {
	OrderID         string          `json:"order_id"`
	BuyerID         string          `json:"buyer_id"`
	BuyerName       string          `json:"buyer_name"`
	Email           string          `json:"email"`
	Name            string          `json:"name"`
	ProductName     string          `json:"product_name"`
	Quantity        int             `json:"quantity"`
	TotalPrice      int             `json:"total_price"`
	DiscountAmount  int             `json:"discount_amount"`
	PaymentMethod   string          `json:"payment_method"`
	Items           []orderLineItem `json:"items"`
	SessionTitle    string          `json:"session_title,omitempty"`
	ShippingName    string          `json:"shipping_name,omitempty"`
	ShippingPhone   string          `json:"shipping_phone,omitempty"`
	ShippingAddress string          `json:"shipping_address,omitempty"`
}

type paymentSuccessEvent struct {
	OrderID         string          `json:"order_id"`
	BuyerID         string          `json:"buyer_id"`
	Method          string          `json:"method"`
	TransID         string          `json:"trans_id"`
	Amount          int             `json:"amount"`
	DiscountAmount  int             `json:"discount_amount"`
	Email           string          `json:"email"`
	Name            string          `json:"name"`
	Items           []orderLineItem `json:"items"`
	ShippingName    string          `json:"shipping_name,omitempty"`
	ShippingPhone   string          `json:"shipping_phone,omitempty"`
	ShippingAddress string          `json:"shipping_address,omitempty"`
}

type orderCancelledEvent struct {
	OrderID   string `json:"order_id"`
	BuyerID   string `json:"buyer_id"`
	ProductID string `json:"product_id,omitempty"`
	Quantity  int    `json:"quantity,omitempty"`
	Reason    string `json:"reason,omitempty"`
	Email     string `json:"email"`
	Name      string `json:"name"`
}

func handleWelcome(emailer *notify.Email, log *slog.Logger) events.HandlerFunc {
	return func(ctx context.Context, data []byte) error {
		ev, err := decode[userEvent](data)
		if err != nil {
			return err
		}
		subject, body := notify.TmplWelcome(ev.Name)
		if err := emailer.Send(ev.Email, subject, body); err != nil {
			log.Warn("welcome email failed", "to", ev.Email, "err", err)
			return err
		}
		log.Info("welcome sent", "to", ev.Email)
		return nil
	}
}

func handleOTP(emailer *notify.Email, log *slog.Logger) events.HandlerFunc {
	return func(ctx context.Context, data []byte) error {
		ev, err := decode[otpEvent](data)
		if err != nil {
			return err
		}
		subject, body := notify.TmplOTP(ev.Name, ev.OTP)
		if err := emailer.Send(ev.Email, subject, body); err != nil {
			log.Warn("otp email failed", "to", ev.Email, "err", err)
			return err
		}
		log.Info("otp sent", "to", ev.Email)
		return nil
	}
}

func handlePasswordReset(emailer *notify.Email, log *slog.Logger, clientURL string) events.HandlerFunc {
	return func(ctx context.Context, data []byte) error {
		ev, err := decode[passwordResetEvent](data)
		if err != nil {
			return err
		}
		link := clientURL + "/reset-password?token=" + ev.ResetToken
		subject, body := notify.TmplPasswordReset(ev.Name, link)
		if err := emailer.Send(ev.Email, subject, body); err != nil {
			log.Warn("reset email failed", "to", ev.Email, "err", err)
			return err
		}
		log.Info("reset sent", "to", ev.Email)
		return nil
	}
}

// methodLabel returns a Vietnamese display label for the payment method
// recorded on the order. The raw values come from FE (`cod`) or the
// payment gateway (`MoMo`, `VNPay`, `ZaloPay`).
func methodLabel(method string) string {
	switch strings.ToLower(method) {
	case "cod":
		return "Tiền mặt khi nhận hàng (COD)"
	case "momo":
		return "Ví MoMo"
	case "zalopay":
		return "ZaloPay"
	case "vnpay":
		return "VNPay"
	default:
		return method
	}
}

func toPaymentItems(in []orderLineItem) []notify.PaymentItem {
	out := make([]notify.PaymentItem, len(in))
	for i, it := range in {
		out[i] = notify.PaymentItem{Name: it.Name, Quantity: it.Quantity, Price: it.Price}
	}
	return out
}

func handleOrderCreated(emailer *notify.Email, log *slog.Logger) events.HandlerFunc {
	return func(ctx context.Context, data []byte) error {
		ev, err := decode[orderEvent](data)
		if err != nil {
			return err
		}
		if ev.Email == "" {
			log.Info("order created (no email)", "order_id", ev.OrderID)
			return nil
		}
		// For COD the order is committed at creation → this is also the
		// receipt the buyer expects. We re-use TmplPaymentSuccess (rich
		// itemized layout) with the COD label. For online methods we
		// SKIP here and let payment.success drive the receipt once the
		// gateway confirms — otherwise the buyer would get a misleading
		// "thanh toán thành công" email before they've actually paid.
		if strings.ToLower(ev.PaymentMethod) != "cod" {
			log.Info("order created (online — receipt deferred to payment.success)",
				"order_id", ev.OrderID, "method", ev.PaymentMethod)
			return nil
		}
		name := ev.Name
		if name == "" {
			name = ev.BuyerName
		}
		subject, body := notify.TmplPaymentSuccess(notify.PaymentSuccessInput{
			Name:            name,
			OrderID:         ev.OrderID,
			Method:          methodLabel(ev.PaymentMethod),
			TransactionID:   "—",
			TotalPrice:      ev.TotalPrice,
			DiscountAmount:  ev.DiscountAmount,
			Items:           toPaymentItems(ev.Items),
			ShippingName:    ev.ShippingName,
			ShippingPhone:   ev.ShippingPhone,
			ShippingAddress: ev.ShippingAddress,
		})
		if err := emailer.Send(ev.Email, subject, body); err != nil {
			log.Warn("order email failed", "to", ev.Email, "err", err)
			return err
		}
		log.Info("order email sent", "to", ev.Email, "order_id", ev.OrderID, "total", ev.TotalPrice)
		return nil
	}
}

func handlePaymentSuccess(emailer *notify.Email, log *slog.Logger) events.HandlerFunc {
	return func(ctx context.Context, data []byte) error {
		ev, err := decode[paymentSuccessEvent](data)
		if err != nil {
			return err
		}
		if ev.Email == "" {
			log.Info("payment success (no email)", "order_id", ev.OrderID)
			return nil
		}
		subject, body := notify.TmplPaymentSuccess(notify.PaymentSuccessInput{
			Name:            ev.Name,
			OrderID:         ev.OrderID,
			Method:          methodLabel(ev.Method),
			TransactionID:   ev.TransID,
			TotalPrice:      ev.Amount,
			DiscountAmount:  ev.DiscountAmount,
			Items:           toPaymentItems(ev.Items),
			ShippingName:    ev.ShippingName,
			ShippingPhone:   ev.ShippingPhone,
			ShippingAddress: ev.ShippingAddress,
		})
		if err := emailer.Send(ev.Email, subject, body); err != nil {
			log.Warn("payment email failed", "to", ev.Email, "err", err)
			return err
		}
		log.Info("payment success sent", "to", ev.Email, "order_id", ev.OrderID, "total", ev.Amount)
		return nil
	}
}

func handleOrderCancelled(emailer *notify.Email, log *slog.Logger) events.HandlerFunc {
	return func(ctx context.Context, data []byte) error {
		ev, err := decode[orderCancelledEvent](data)
		if err != nil {
			return err
		}
		log.Info("order cancelled", "order_id", ev.OrderID, "reason", ev.Reason)
		return nil
	}
}

// ── Recording / VOD upload ───────────────────────────────────────────────────

type recordingEvent struct {
	SessionID   string `json:"session_id"`
	StreamKey   string `json:"stream_key"`
	SrsFilePath string `json:"srs_file_path"` // path relative to DVR root, e.g. "live/live_xxx.123.flv"
	DurationSec int    `json:"duration_sec"`
}

// handleRecording is fired when SRS finishes writing a DVR .flv file.
// It remuxes FLV → MP4 with FFmpeg (no re-encode, ~instant), uploads the
// MP4 to Cloudflare R2 under videos/replays/<sessionId>/<ts>.mp4, then sets
// live_sessions.vod_mp4_url so viewers can replay the broadcast.
//
// Requirements:
//   - DVR_HOST_PATH env var → host filesystem path that SRS bind-mounts.
//     Default: "../infra/dvr" (relative to backend/ working dir).
//   - `ffmpeg` on PATH.
//   - R2 credentials configured (otherwise the upload is skipped with a warning).
//
// handleRecording is fired when SRS finishes writing a DVR .flv file.
// Pipeline:
//  1. Look up the session + its chat + host action events from DB.
//  2. Run the bake pipeline (vod.Bake): re-encode FLV → MP4 with
//     chat subtitles burned in via libass. Phase 2 will also overlay
//     pin/coupon/bot PNGs.
//  3. Upload final MP4 to R2 at videos/replays/<sessionId>/<ts>.mp4 and
//     set live_sessions.vod_mp4_url.
//
// This is the SLOW path — full re-encode at ~1× realtime on a laptop
// CPU. The previous `-c copy` remux is gone because we can't bake
// overlays without re-encoding video frames.
func handleRecording(r2 *storage.R2, repo *live.SessionRepository, eventsRepo *live.EventRepository, dvrRoot string, log *slog.Logger) events.HandlerFunc {
	return func(ctx context.Context, data []byte) error {
		ev, err := decode[recordingEvent](data)
		if err != nil {
			return err
		}
		log.Info("recording started",
			"session_id", ev.SessionID,
			"file", ev.SrsFilePath,
			"duration_sec", ev.DurationSec,
		)

		sessUUID, err := uuid.Parse(ev.SessionID)
		if err != nil {
			return fmt.Errorf("invalid session id: %w", err)
		}
		recID, _ := repo.InsertRecording(ctx, sessUUID, ev.SrsFilePath, ev.DurationSec)

		flvPath := filepath.Join(dvrRoot, filepath.FromSlash(ev.SrsFilePath))
		if _, err := os.Stat(flvPath); err != nil {
			msg := fmt.Sprintf("flv not found at %s: %v", flvPath, err)
			log.Warn("recording skip", "err", msg)
			_ = repo.MarkRecordingFailed(ctx, recID, msg)
			return nil // don't retry — file isn't going to appear
		}

		// 1. Load session + timeline (chat + events).
		sess, err := repo.GetByID(ctx, sessUUID)
		if err != nil {
			_ = repo.MarkRecordingFailed(ctx, recID, "get session: "+err.Error())
			return err
		}
		chats, _ := repo.TimelineChats(ctx, sessUUID, 10000)
		evts, _ := eventsRepo.ListBySession(ctx, sessUUID)
		products, _ := repo.ListProducts(ctx, sessUUID)

		// Video duration — prefer session.ended_at - started_at since
		// that's set by the explicit /end call. Fall back to event
		// duration_sec if ended_at is missing (worker fired before
		// MarkEnded landed).
		var videoDur time.Duration
		if sess.EndedAt != nil {
			videoDur = sess.EndedAt.Sub(sess.StartedAt)
		} else if ev.DurationSec > 0 {
			videoDur = time.Duration(ev.DurationSec) * time.Second
		}

		// 2. Bake (re-encode + subtitles + overlays burned in).
		workDir := filepath.Join(os.TempDir(), "tropia-bake-"+sessUUID.String())
		bakedPath, bakeErr := vod.Bake(ctx, vod.BakeInput{
			SessionID:     sessUUID,
			FLVPath:       flvPath,
			SessionStart:  sess.StartedAt,
			Chats:         chats,
			Events:        evts,
			Products:      products,
			VideoDuration: videoDur,
			WorkDir:       workDir,
			Logger:        log,
		})
		if bakeErr != nil {
			_ = repo.MarkRecordingFailed(ctx, recID, bakeErr.Error())
			_ = os.RemoveAll(workDir)
			return bakeErr
		}

		// 3. Upload baked MP4 to R2.
		if r2 == nil {
			msg := "R2 not configured — skipping upload"
			log.Warn(msg, "session", ev.SessionID, "local_mp4", bakedPath)
			_ = repo.MarkRecordingFailed(ctx, recID, msg)
			_ = os.RemoveAll(workDir)
			return nil
		}
		mp4Bytes, err := os.ReadFile(bakedPath)
		if err != nil {
			_ = repo.MarkRecordingFailed(ctx, recID, err.Error())
			_ = os.RemoveAll(workDir)
			return err
		}
		r2Key := fmt.Sprintf("videos/replays/%s/%d.mp4", ev.SessionID, time.Now().Unix())
		url, err := r2.Upload(ctx, r2Key, "video/mp4", mp4Bytes)
		if err != nil {
			_ = repo.MarkRecordingFailed(ctx, recID, err.Error())
			_ = os.RemoveAll(workDir)
			return err
		}

		// 4. Persist URL + cleanup.
		if err := repo.SetVodURLs(ctx, sessUUID, url, ""); err != nil {
			log.Warn("update vod_url failed", "err", err)
		}
		_ = repo.MarkRecordingUploaded(ctx, recID, r2Key, int64(len(mp4Bytes)))

		// Best-effort cleanup. Keep FLV on error so you can re-process
		// by hand; if we got this far the FLV has done its job.
		_ = os.Remove(flvPath)
		_ = os.RemoveAll(workDir)

		log.Info("recording baked + uploaded",
			"session", ev.SessionID,
			"size_mb", len(mp4Bytes)/(1024*1024),
			"chats", len(chats),
			"events", len(evts),
			"url", url,
		)
		return nil
	}
}

// ── Video overlay bake ───────────────────────────────────────────────────────

type videoCreatedEvent struct {
	VideoID string `json:"video_id"`
}

const (
	// maxOverlayJobTime bounds one video-overlay bake end-to-end (download +
	// render + ffmpeg + upload). The video-overlay consumer processes clips
	// one at a time, so without a cap a single pathological clip (a slow
	// ffmpeg encode, a stalled download) would wedge the queue and stall every
	// later clip's bake. ffmpeg + R2 calls take this ctx, so the deadline
	// actually kills the encode.
	maxOverlayJobTime = 10 * time.Minute
	// maxClipDownloadBytes caps the raw clip pulled from R2 before baking. The
	// upload route already caps clips at 50MB; this is the same ceiling + a
	// little headroom so a swapped/oversized object can't balloon worker
	// memory + disk.
	maxClipDownloadBytes = 64 << 20
)

// handleVideoOverlay bakes the static-overlay copy of a freshly-posted clip.
// It loads the video + its tagged products/coupons, downloads the raw MP4 from
// R2 over HTTP, renders the info overlay PNG, composites it with FFmpeg, and
// uploads the result to videos/clips/<id>/overlay.mp4, then records
// videos.overlay_url. The feed keeps serving the raw clip throughout — this
// copy is only for download / sharing the clip outside the app.
func handleVideoOverlay(r2 *storage.R2, repo *video.Repository, log *slog.Logger) events.HandlerFunc {
	return func(ctx context.Context, data []byte) error {
		ev, err := decode[videoCreatedEvent](data)
		if err != nil {
			return err
		}
		vidUUID, err := uuid.Parse(ev.VideoID)
		if err != nil {
			return fmt.Errorf("invalid video id: %w", err)
		}

		// Bound the whole job so one bad clip can't wedge the single-threaded
		// video-overlay consumer (the deadline propagates into ffmpeg + R2).
		ctx, cancel := context.WithTimeout(ctx, maxOverlayJobTime)
		defer cancel()

		// Load the clip with its joined shop / products / coupons (viewer=Nil).
		v, err := repo.GetByID(ctx, uuid.Nil, vidUUID)
		if errors.Is(err, video.ErrNotFound) {
			return nil // deleted before we got to it — drop the job
		}
		if err != nil {
			return err
		}
		if r2 == nil {
			log.Warn("video overlay skip: R2 not configured", "video_id", ev.VideoID)
			_ = repo.SetOverlayStatus(ctx, vidUUID, "skipped")
			return nil
		}
		_ = repo.SetOverlayStatus(ctx, vidUUID, "processing")

		workDir := filepath.Join(os.TempDir(), "tropia-overlay-"+vidUUID.String())
		defer os.RemoveAll(workDir)
		if err := os.MkdirAll(workDir, 0o755); err != nil {
			_ = repo.SetOverlayStatus(ctx, vidUUID, "failed")
			return err
		}

		// 1. Download the raw clip from its public R2 URL.
		srcPath := filepath.Join(workDir, "source.mp4")
		if err := httpDownload(ctx, v.VideoURL, srcPath, maxClipDownloadBytes); err != nil {
			_ = repo.SetOverlayStatus(ctx, vidUUID, "failed")
			return fmt.Errorf("download raw clip: %w", err)
		}

		// 1b. Probe the clip's real display dimensions so the overlay PNG is
		// rendered at the clip's true aspect. Clients — especially Flutter web,
		// which can't read a file:// preview — POST width=height=0, which would
		// default the overlay to 1080×1920 and let scale2ref stretch it onto a
		// clip with a different aspect ratio. ffprobe is authoritative; on
		// failure we keep whatever the client reported.
		if w, h, perr := vod.ProbeVideoSize(ctx, srcPath); perr == nil {
			v.Width, v.Height = w, h
		} else {
			log.Warn("video overlay: ffprobe failed; using client dims",
				"video_id", ev.VideoID, "client_w", v.Width, "client_h", v.Height, "err", perr)
		}

		// 2. Render the static overlay PNG from the clip's metadata.
		pngPath := filepath.Join(workDir, "overlay.png")
		if err := vod.RenderFeedOverlay(ctx, buildFeedOverlayInput(v), pngPath); err != nil {
			_ = repo.SetOverlayStatus(ctx, vidUUID, "failed")
			return fmt.Errorf("render overlay: %w", err)
		}

		// 3. Composite overlay over the clip (FFmpeg).
		bakedPath, err := vod.BakeFeedOverlay(ctx, vod.FeedBakeInput{
			SrcPath: srcPath, OverlayPNG: pngPath, WorkDir: workDir, Logger: log,
		})
		if err != nil {
			_ = repo.SetOverlayStatus(ctx, vidUUID, "failed")
			return err
		}

		// 4. Upload alongside the raw clip and record the URL.
		mp4Bytes, err := os.ReadFile(bakedPath)
		if err != nil {
			_ = repo.SetOverlayStatus(ctx, vidUUID, "failed")
			return err
		}
		key := fmt.Sprintf("videos/clips/%s/overlay.mp4", vidUUID)
		url, err := r2.Upload(ctx, key, "video/mp4", mp4Bytes)
		if err != nil {
			_ = repo.SetOverlayStatus(ctx, vidUUID, "failed")
			return err
		}
		if err := repo.SetOverlayURL(ctx, vidUUID, url); err != nil {
			log.Warn("set overlay_url failed", "err", err)
		}
		log.Info("video overlay baked + uploaded",
			"video_id", ev.VideoID, "size_mb", len(mp4Bytes)/(1024*1024), "url", url)
		return nil
	}
}

// buildFeedOverlayInput maps a video record (with joined shop / products /
// coupons) to the static overlay layer the renderer burns in.
func buildFeedOverlayInput(v *video.Video) vod.FeedOverlayInput {
	handle := ""
	switch {
	case v.ShopName != nil && *v.ShopName != "":
		handle = "@" + *v.ShopName
	case v.UserName != nil && *v.UserName != "":
		handle = "@" + *v.UserName
	}
	caption := ""
	if v.Caption != nil {
		caption = *v.Caption
	}
	products := make([]vod.Product, 0, len(v.Products))
	for _, p := range v.Products {
		price := float64(p.BasePrice)
		if p.SalePrice != nil {
			price = float64(*p.SalePrice)
		}
		// Active flash sale → use the flash price + flag the card (mirrors the
		// feed's displayPrice priority: flash > sale > base).
		flash := p.FlashPrice != nil && p.FlashEndsAt != nil && p.FlashEndsAt.After(time.Now())
		if flash {
			price = float64(*p.FlashPrice)
		}
		img := ""
		if p.ImageURL != nil {
			img = *p.ImageURL
		}
		products = append(products, vod.Product{Name: p.Name, SalePrice: price, ImageURL: img, Flash: flash})
	}
	labels := make([]string, 0, len(v.Coupons))
	for _, c := range v.Coupons {
		if c.DiscountType == "percent" {
			labels = append(labels, fmt.Sprintf("Giảm %.0f%%", c.DiscountValue))
		} else {
			labels = append(labels, "Giảm "+vod.FormatVND(c.DiscountValue))
		}
	}
	// Avatar for the rail head: prefer the shop logo, fall back to the creator's.
	avatar := ""
	switch {
	case v.ShopAvatar != nil && *v.ShopAvatar != "":
		avatar = *v.ShopAvatar
	case v.UserAvatar != nil && *v.UserAvatar != "":
		avatar = *v.UserAvatar
	}
	return vod.FeedOverlayInput{
		Width:          v.Width,
		Height:         v.Height,
		Handle:         handle,
		Caption:        caption,
		Hashtags:       v.Hashtags,
		Products:       products,
		CouponLabels:   labels,
		AvatarURL:      avatar,
		LikeCount:      v.LikeCount,
		CommentCount:   v.CommentCount,
		ShareCount:     v.ShareCount,
		ShopHasVoucher: v.ShopHasVoucher,
	}
}

// httpDownload fetches url into dstPath (pulls the raw clip from public R2),
// refusing to write more than maxBytes. The clip URL is constrained to our
// own store at create time, but the download still goes through the SSRF
// guard as defense-in-depth so a misconfigured/poisoned URL can't make the
// worker hit an internal host, and the size cap stops a swapped/oversized
// object from ballooning worker memory + disk.
func httpDownload(ctx context.Context, url, dstPath string, maxBytes int64) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	resp, err := safefetch.Default.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("GET %s: status %d", url, resp.StatusCode)
	}
	f, err := os.Create(dstPath)
	if err != nil {
		return err
	}
	defer f.Close()
	// LimitReader(maxBytes+1) so a file exactly at the cap is still accepted
	// while anything larger trips the guard below.
	n, err := io.Copy(f, io.LimitReader(resp.Body, maxBytes+1))
	if err != nil {
		return err
	}
	if n > maxBytes {
		return fmt.Errorf("clip exceeds %d bytes", maxBytes)
	}
	return nil
}

// ── DVR cleanup sweeper ─────────────────────────────────────────────────────

// runDVRSweeper walks dvrRoot every `interval` and removes any .flv file
// whose mtime is older than `maxAge`. Recurses one level so it handles
// the SRS layout `<dvrRoot>/<app>/<stream>.<ts>.flv`. Errors are logged
// but never fatal — a missing dir on first launch is fine.
func runDVRSweeper(ctx context.Context, dvrRoot string, interval, maxAge time.Duration, log *slog.Logger) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	// Initial sweep on startup so a crashed worker that left orphans
	// behind doesn't have to wait for the first tick.
	sweepDVR(dvrRoot, maxAge, log)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			sweepDVR(dvrRoot, maxAge, log)
		}
	}
}

func sweepDVR(dvrRoot string, maxAge time.Duration, log *slog.Logger) {
	cutoff := time.Now().Add(-maxAge)
	var removed, scanned int
	err := filepath.Walk(dvrRoot, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // skip unreadable entries
		}
		if info.IsDir() {
			return nil
		}
		if filepath.Ext(path) != ".flv" {
			return nil
		}
		scanned++
		if info.ModTime().After(cutoff) {
			return nil
		}
		if rmErr := os.Remove(path); rmErr != nil {
			log.Warn("dvr sweep: remove failed", "path", path, "err", rmErr)
			return nil
		}
		removed++
		return nil
	})
	if err != nil {
		log.Warn("dvr sweep: walk failed", "root", dvrRoot, "err", err)
		return
	}
	if removed > 0 {
		log.Info("dvr sweep", "root", dvrRoot, "scanned", scanned, "removed", removed, "older_than", maxAge)
	}
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

// parseDurEnv reads a time.Duration from env (e.g. "4h", "720h"), falling
// back to def when unset/invalid.
func parseDurEnv(key string, def time.Duration) time.Duration {
	if v := os.Getenv(key); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return def
}

// ── Live max-duration sweeper ───────────────────────────────────────────────

// runLiveDurationSweeper force-ends sessions live longer than maxDuration —
// the platform's max live-time cap. Runs every `interval`.
func runLiveDurationSweeper(ctx context.Context, repo *live.SessionRepository, interval, maxDuration time.Duration, log *slog.Logger) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	sweepLiveDuration(ctx, repo, maxDuration, log)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			sweepLiveDuration(ctx, repo, maxDuration, log)
		}
	}
}

func sweepLiveDuration(ctx context.Context, repo *live.SessionRepository, maxDuration time.Duration, log *slog.Logger) {
	keys, err := repo.EndStaleSessions(ctx, maxDuration)
	if err != nil {
		log.Warn("live duration sweep: failed", "err", err)
		return
	}
	if len(keys) > 0 {
		log.Info("live duration sweep: ended over-long sessions",
			"count", len(keys), "max_duration", maxDuration, "stream_keys", keys)
	}
}

// ── R2 VOD retention sweeper ─────────────────────────────────────────────────

// runR2RetentionSweeper deletes recordings older than maxAge from Cloudflare
// R2 (VOD kept 30 days by default, then removed). Runs every `interval`.
func runR2RetentionSweeper(ctx context.Context, repo *live.SessionRepository, r2 *storage.R2, interval, maxAge time.Duration, log *slog.Logger) {
	if r2 == nil {
		log.Info("r2 retention sweeper disabled (R2 not configured)")
		return
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	sweepR2Retention(ctx, repo, r2, maxAge, log)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			sweepR2Retention(ctx, repo, r2, maxAge, log)
		}
	}
}

func sweepR2Retention(ctx context.Context, repo *live.SessionRepository, r2 *storage.R2, maxAge time.Duration, log *slog.Logger) {
	recs, err := repo.ExpiredRecordings(ctx, maxAge, 200)
	if err != nil {
		log.Warn("r2 retention sweep: list failed", "err", err)
		return
	}
	var deleted int
	for _, rec := range recs {
		if err := r2.Delete(ctx, rec.R2Key); err != nil {
			log.Warn("r2 retention: delete failed", "key", rec.R2Key, "err", err)
			continue
		}
		if err := repo.MarkRecordingExpired(ctx, rec.ID, rec.SessionID); err != nil {
			log.Warn("r2 retention: mark expired failed", "recording", rec.ID, "err", err)
			continue
		}
		deleted++
	}
	if deleted > 0 {
		log.Info("r2 retention sweep: deleted expired recordings", "deleted", deleted, "older_than", maxAge)
	}
}
