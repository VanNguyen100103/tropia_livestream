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
//
// Each handler runs in its own goroutine with its own consumer name so
// Redis Streams' consumer-group semantics give us at-least-once delivery
// + automatic retry on handler error (via PEL).
//
// Usage:
//   go run ./cmd/worker
//   make worker
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"log/slog"
	"os"
	"os/exec"
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
	"github.com/tropia/backend/internal/storage"
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
		{topic: "recording.created", group: "vod-uploader", handler: handleRecording(r2, sessRepo, dvrRoot, logger)},
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

	logger.Info("worker running", "subscriptions", len(subs))

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

type orderEvent struct {
	OrderID        string `json:"order_id"`
	BuyerID        string `json:"buyer_id"`
	BuyerName      string `json:"buyer_name"`
	ProductName    string `json:"product_name"`
	Quantity       int    `json:"quantity"`
	TotalPrice     int    `json:"total_price"`
	DiscountAmount int    `json:"discount_amount"`
	SessionTitle   string `json:"session_title,omitempty"`
}

type paymentSuccessEvent struct {
	OrderID  string `json:"order_id"`
	BuyerID  string `json:"buyer_id"`
	Method   string `json:"method"`
	TransID  string `json:"trans_id"`
	Amount   int    `json:"amount"`
	Email    string `json:"email"`
	Name     string `json:"name"`
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

func handleOrderCreated(emailer *notify.Email, log *slog.Logger) events.HandlerFunc {
	return func(ctx context.Context, data []byte) error {
		ev, err := decode[orderEvent](data)
		if err != nil {
			return err
		}
		// We don't have buyer email in payload yet — production would look up.
		// For now log and skip email if email is missing.
		if ev.BuyerName == "" {
			log.Info("order created (no email lookup wired)", "order_id", ev.OrderID)
			return nil
		}
		log.Info("order created", "order_id", ev.OrderID, "buyer", ev.BuyerName, "total", ev.TotalPrice)
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
			Name:          ev.Name,
			OrderID:       ev.OrderID,
			Method:        ev.Method,
			TransactionID: ev.TransID,
			TotalPrice:    ev.Amount,
			// Items/DiscountAmount left empty for now — fill when payment
			// event publisher includes line items (TODO in commerce.OrderService).
		})
		if err := emailer.Send(ev.Email, subject, body); err != nil {
			log.Warn("payment email failed", "to", ev.Email, "err", err)
			return err
		}
		log.Info("payment success sent", "to", ev.Email, "order_id", ev.OrderID)
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
	SrsFilePath string `json:"srs_file_path"`  // path relative to DVR root, e.g. "live/live_xxx.123.flv"
	DurationSec int    `json:"duration_sec"`
}

// handleRecording is fired when SRS finishes writing a DVR .flv file.
// It remuxes FLV → MP4 with FFmpeg (no re-encode, ~instant), uploads the
// MP4 to Cloudflare R2 under videos/vod/<sessionId>/<ts>.mp4, then sets
// live_sessions.vod_mp4_url so viewers can replay the broadcast.
//
// Requirements:
//   - DVR_HOST_PATH env var → host filesystem path that SRS bind-mounts.
//     Default: "../infra/dvr" (relative to backend/ working dir).
//   - `ffmpeg` on PATH.
//   - R2 credentials configured (otherwise the upload is skipped with a warning).
func handleRecording(r2 *storage.R2, repo *live.SessionRepository, dvrRoot string, log *slog.Logger) events.HandlerFunc {
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

		// 1. Remux FLV → MP4 (no re-encode). Output beside the input.
		mp4Path := strings.TrimSuffix(flvPath, filepath.Ext(flvPath)) + ".mp4"
		cmd := exec.CommandContext(ctx, "ffmpeg",
			"-y",                  // overwrite
			"-i", flvPath,         // input
			"-c", "copy",          // no re-encode (fast)
			"-movflags", "+faststart", // MOOV atom at the front (web-friendly)
			mp4Path,
		)
		if out, err := cmd.CombinedOutput(); err != nil {
			msg := fmt.Sprintf("ffmpeg failed: %v — %s", err, truncate(string(out), 400))
			log.Warn("remux failed", "session", ev.SessionID, "err", msg)
			_ = repo.MarkRecordingFailed(ctx, recID, msg)
			return err // worker will retry on next read of the pending entry
		}

		// 2. Upload MP4 to R2.
		if r2 == nil {
			msg := "R2 not configured — skipping upload"
			log.Warn(msg, "session", ev.SessionID, "local_mp4", mp4Path)
			_ = repo.MarkRecordingFailed(ctx, recID, msg)
			return nil
		}
		mp4Bytes, err := os.ReadFile(mp4Path)
		if err != nil {
			_ = repo.MarkRecordingFailed(ctx, recID, err.Error())
			return err
		}
		r2Key := fmt.Sprintf("videos/vod/%s/%d.mp4", ev.SessionID, time.Now().Unix())
		url, err := r2.Upload(ctx, r2Key, "video/mp4", mp4Bytes)
		if err != nil {
			_ = repo.MarkRecordingFailed(ctx, recID, err.Error())
			return err
		}

		// 3. Persist URL + cleanup.
		if err := repo.SetVodURLs(ctx, sessUUID, url, ""); err != nil {
			log.Warn("update vod_url failed", "err", err)
		}
		_ = repo.MarkRecordingUploaded(ctx, recID, r2Key, int64(len(mp4Bytes)))

		// Best-effort cleanup of local files (FLV + MP4); keep on error so
		// you can re-process by hand.
		_ = os.Remove(flvPath)
		_ = os.Remove(mp4Path)

		log.Info("recording uploaded",
			"session", ev.SessionID,
			"size_mb", len(mp4Bytes)/(1024*1024),
			"url", url,
		)
		return nil
	}
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
