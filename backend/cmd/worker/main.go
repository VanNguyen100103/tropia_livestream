// Command worker is the background job runner for Tropia. It consumes
// Redis Streams events published by the api binary and reacts to them
// (mostly: send transactional email).
//
// Topics:
//   - user.registered         → welcome email
//   - auth.email_otp          → OTP email
//   - auth.password_reset     → password reset link email
//   - order.created           → order confirmation email
//   - payment.success         → payment receipt email
//   - order.cancelled         → cancellation email
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
	"log"
	"log/slog"
	"os"
	"os/signal"
	"sync"
	"syscall"

	"github.com/joho/godotenv"

	"github.com/tropia/backend/internal/config"
	"github.com/tropia/backend/internal/database"
	"github.com/tropia/backend/internal/events"
	"github.com/tropia/backend/internal/httpx"
	"github.com/tropia/backend/internal/notify"
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

	bus := events.New(rds, logger)

	emailer := notify.NewEmail(notify.EmailConfig{
		Host:     getEnvOr("EMAIL_HOST", "smtp.gmail.com"),
		Port:     587,
		Username: os.Getenv("EMAIL_USERNAME"),
		Password: os.Getenv("EMAIL_PASSWORD"),
		FromName: getEnvOr("EMAIL_FROM_NAME", "Tropia"),
	})
	clientURL := getEnvOr("CLIENT_URL", "http://localhost:8080")

	subs := []subscription{
		{topic: "user.registered", group: "notify-welcome", handler: handleWelcome(emailer, logger)},
		{topic: "auth.email_otp", group: "notify-otp", handler: handleOTP(emailer, logger)},
		{topic: "auth.password_reset", group: "notify-reset", handler: handlePasswordReset(emailer, logger, clientURL)},
		{topic: "order.created", group: "notify-order-created", handler: handleOrderCreated(emailer, logger)},
		{topic: "payment.success", group: "notify-payment-success", handler: handlePaymentSuccess(emailer, logger)},
		{topic: "order.cancelled", group: "notify-order-cancelled", handler: handleOrderCancelled(emailer, logger)},
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
