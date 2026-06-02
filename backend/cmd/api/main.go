package main

import (
	"context"
	"errors"
	"log"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/joho/godotenv"

	"github.com/tropia/backend/internal/ai"
	"github.com/tropia/backend/internal/audit"
	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/cache"
	"github.com/tropia/backend/internal/catalog"
	"github.com/tropia/backend/internal/commerce"
	"github.com/tropia/backend/internal/config"
	"github.com/tropia/backend/internal/database"
	"github.com/tropia/backend/internal/events"
	"github.com/tropia/backend/internal/httpx"
	"github.com/tropia/backend/internal/live"
	"github.com/tropia/backend/internal/payment"
	"github.com/tropia/backend/internal/shops"
	"github.com/tropia/backend/internal/srs"
	"github.com/tropia/backend/internal/storage"
)

func main() {
	// Load env
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

	gin.SetMode(cfg.GinMode)
	logger := httpx.NewLogger(os.Getenv("NODE_ENV"))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Postgres
	db, err := database.NewPostgres(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("postgres: %v", err)
	}
	defer db.Close()
	logger.Info("postgres connected")

	// Redis
	rds, err := database.NewRedis(ctx, cfg.RedisAddr, cfg.RedisPassword, cfg.RedisDB)
	if err != nil {
		log.Fatalf("redis: %v", err)
	}
	defer rds.Close()
	logger.Info("redis connected")

	cc := cache.New(rds)
	bus := events.New(rds, logger)

	// Optional integrations
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
			logger.Info("r2 connected")
		}
	}

	momo := payment.NewMoMo(payment.MoMoConfig{
		PartnerCode: os.Getenv("MOMO_PARTNER_CODE"),
		AccessKey:   os.Getenv("MOMO_ACCESS_KEY"),
		SecretKey:   os.Getenv("MOMO_SECRET_KEY"),
		APIURL:      getEnvOr("MOMO_API_URL", "https://test-payment.momo.vn"),
		RedirectURL: os.Getenv("MOMO_REDIRECT_URL"),
		IPNURL:      os.Getenv("MOMO_IPN_URL"),
	})
	vnpay := payment.NewVNPay(payment.VNPayConfig{
		TMNCode:    os.Getenv("VNP_TMN_CODE"),
		HashSecret: os.Getenv("VNP_HASH_SECRET"),
		URL:        getEnvOr("VNP_URL", "https://sandbox.vnpayment.vn/paymentv2/vpcpay.html"),
		ReturnURL:  os.Getenv("VNP_RETURN_URL"),
	})
	zalopay := payment.NewZaloPay(payment.ZaloPayConfig{
		AppID:       os.Getenv("ZALOPAY_APP_ID"),
		Key1:        os.Getenv("ZALOPAY_KEY1"),
		Key2:        os.Getenv("ZALOPAY_KEY2"),
		APICreate:   getEnvOr("ZALOPAY_API_CREATE", "https://sb-openapi.zalopay.vn/v2/create"),
		APIQuery:    getEnvOr("ZALOPAY_API_QUERY", "https://sb-openapi.zalopay.vn/v2/query"),
		CallbackURL: os.Getenv("ZALOPAY_CALLBACK_URL"),
		RedirectURL: os.Getenv("ZALOPAY_REDIRECT_URL"),
	})

	// Email sending lives in cmd/worker, not here.

	deepseek := ai.NewDeepSeek(os.Getenv("DEEPSEEK_API_KEY"))

	// JWT
	jwtSvc := auth.NewService(cfg.JWTAccessSecret, cfg.JWTRefreshSecret, cfg.JWTAccessTTL, cfg.JWTRefreshTTL)

	// Repos
	authRepo := auth.NewRepository(db)
	shopRepo := shops.NewRepository(db)
	catRepo := catalog.NewCategoryRepository(db)
	prodRepo := catalog.NewProductRepository(db)
	sessRepo := live.NewSessionRepository(db)
	liveEventsRepo := live.NewEventRepository(db)
	muteRepo := live.NewChatMuteRepository(db)
	cartRepo := commerce.NewCartRepository(db)
	orderRepo := commerce.NewOrderRepository(db)
	cpnRepo := commerce.NewCouponRepository(db)
	auditRepo := audit.NewRepository(db)

	// Services — wired with the event bus so writes publish to Redis Streams
	// for the worker binary to pick up.
	authSvc := auth.NewAuthService(authRepo, jwtSvc, rds, cc).WithEvents(bus)
	tokenSigner, err := live.NewTokenSignerFromJSON(cfg.SRSTokenKeysJSON, cfg.SRSTokenCurrentKid, cfg.SRSTokenTTL)
	if err != nil {
		log.Fatalf("token signer: %v (check SRS_TOKEN_KEYS_JSON / SRS_TOKEN_CURRENT_KID)", err)
	}
	if tokenSigner.Enabled() {
		log.Printf("token signer: ENABLED (current kid=%s, ttl=%s)", cfg.SRSTokenCurrentKid, cfg.SRSTokenTTL)
	} else {
		log.Printf("token signer: disabled (SRS_TOKEN_KEYS_JSON empty — publish/playback URLs are unsigned)")
	}
	liveSvc := live.NewService(nil, live.ServiceConfig{
		RTMPHost: cfg.SRSRtmpHost,
		HLSHost:  cfg.SRSHlsHost,
		WHIPHost: cfg.SRSWhipHost,
		SRTPort:  10080,
	}).WithTokenSigner(tokenSigner)
	orderSvc := commerce.NewOrderService(db, orderRepo, cartRepo, cpnRepo, cc).
		WithEvents(bus).
		WithBuyerLookup(authBuyerLookup{repo: authRepo})

	// HTTP
	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(httpx.RequestID())
	router.Use(httpx.SecurityHeaders())
	router.Use(httpx.AuditLog(logger))
	// Wrap every JSON response in the standard envelope (LIVESTREAM_API.md
	// §1). Registered before ErrorHandler so its buffering writer captures
	// both handler output and error responses.
	router.Use(httpx.EnvelopeWrapper())
	router.Use(httpx.ErrorHandler(logger))
	router.Use(httpx.RequestSizeGuard(64, "/api/upload"))
	// CORS — whitelist per-environment via CORS_ORIGIN. We refuse to boot
	// in release mode if the list is empty (`*` + AllowCredentials is
	// invalid per CORS spec). In dev we fall back to localhost defaults
	// so a forgotten/legacy `CORS_ORIGIN=*` doesn't panic gin-contrib's
	// cors.New (which requires AllowOrigins non-empty when AllowCredentials).
	corsOrigins := cfg.CORSOrigins
	corsCfg := cors.Config{
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization", "X-Request-ID"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}
	if len(corsOrigins) == 0 {
		if gin.Mode() == gin.ReleaseMode {
			log.Fatalf("CORS_ORIGIN must be set to a comma-separated whitelist in release mode (not `*`)")
		}
		// Dev: `flutter run -d chrome` picks a random port, so a fixed
		// whitelist would 403 every restart. Accept any loopback origin
		// (localhost / 127.0.0.1 / 10.0.2.2 — Android emulator → host)
		// regardless of port. Release mode still requires an explicit
		// whitelist via CORS_ORIGIN.
		logger.Warn("CORS_ORIGIN empty/wildcard — dev mode: allowing any loopback origin")
		corsCfg.AllowOriginFunc = func(origin string) bool {
			return strings.HasPrefix(origin, "http://localhost:") ||
				strings.HasPrefix(origin, "http://127.0.0.1:") ||
				strings.HasPrefix(origin, "http://10.0.2.2:")
		}
	} else {
		corsCfg.AllowOrigins = corsOrigins
	}
	router.Use(cors.New(corsCfg))

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"ok": true, "service": "tropia-backend", "ts": time.Now().Unix()})
	})

	// Prometheus
	metrics := httpx.NewMetrics()
	router.Use(metrics.Middleware())
	// Prometheus metrics — gated behind METRICS_TOKEN to keep traffic
	// patterns + business volumes off the public internet. Prometheus
	// server sends the token as `Authorization: Bearer <token>`. Empty
	// token in dev disables the check; release mode requires it.
	metricsToken := os.Getenv("METRICS_TOKEN")
	if gin.Mode() == gin.ReleaseMode && metricsToken == "" {
		log.Fatalf("METRICS_TOKEN must be set in release mode (otherwise /metrics leaks business metrics to the public)")
	}
	router.GET("/metrics", func(c *gin.Context) {
		if metricsToken != "" {
			got := c.GetHeader("Authorization")
			if got != "Bearer "+metricsToken {
				c.Status(http.StatusUnauthorized)
				return
			}
		}
		httpx.MetricsHandler()(c)
	})

	// OpenAPI 3.1 spec — covers /api/auth, /api/live, /api/orders,
	// /api/shops, /api/upload, and the system endpoints. Closes OWASP
	// API9 (Improper Inventory Management). Served as a static file
	// from backend/docs/openapi.yaml. In production, gate behind the
	// same DOCS_TOKEN header so the spec doesn't leak the endpoint
	// surface to drive-by scanners.
	docsToken := os.Getenv("DOCS_TOKEN")
	router.GET("/docs/openapi.yaml", func(c *gin.Context) {
		if docsToken != "" && c.GetHeader("Authorization") != "Bearer "+docsToken {
			c.Status(http.StatusUnauthorized)
			return
		}
		c.File("docs/openapi.yaml")
	})

	authMw := auth.Middleware(jwtSvc)
	sellerMw := auth.RequireRole(auth.RoleSeller, auth.RoleAdmin)
	adminMw := auth.RequireRole(auth.RoleAdmin)
	optAuthMw := optionalAuth(jwtSvc)

	clientURL := getEnvOr("CLIENT_URL", "http://localhost:8080")

	// Auth routes
	authH := auth.NewAPIHandler(authSvc, auth.HandlerConfig{
		GoogleAppDeepLink: os.Getenv("GOOGLE_APP_DEEP_LINK"),
		ClientURL:         clientURL,
		CookieSecure:      gin.Mode() == gin.ReleaseMode,
	})
	authH.Register(router.Group("/api/auth"), authMw, cc)

	googleOAuth := auth.NewGoogleOAuth(authSvc, rds, auth.GoogleOAuthConfig{
		ClientID:     cfg.GoogleClientID,
		ClientSecret: cfg.GoogleClientSecret,
		RedirectURL:  cfg.GoogleRedirectURL,
		DeepLink:     getEnvOr("GOOGLE_APP_DEEP_LINK", "tropia://auth/callback"),
		ClientURL:    clientURL,
	})
	googleOAuth.Register(router.Group("/api/auth"))

	// Live
	// Stream-key provider selection. "local" generates a random key in
	// process; "infra" calls the infra team's stream registry so they
	// can revoke / audit. Production should run "infra" — see
	// docs/SECURITY.md for the API contract.
	var streamKeyProvider live.StreamKeyProvider = live.NewLocalStreamKeyProvider()
	if cfg.StreamKeyProvider == "infra" {
		streamKeyProvider = live.NewInfraStreamKeyProvider(
			cfg.InfraStreamAPIBase,
			cfg.InfraStreamAPIKey,
			live.NewLocalStreamKeyProvider(),
			cfg.StreamKeyProviderAllowFallback,
		)
		log.Printf("stream key provider: infra (base=%s, fallback=%v)",
			cfg.InfraStreamAPIBase, cfg.StreamKeyProviderAllowFallback)
		if gin.Mode() == gin.ReleaseMode && !cfg.StreamKeyProviderAllowFallback &&
			(cfg.InfraStreamAPIBase == "" || cfg.InfraStreamAPIKey == "") {
			log.Fatalf("STREAM_KEY_PROVIDER=infra requires INFRA_STREAM_API_URL and INFRA_STREAM_API_KEY in release mode")
		}
	} else {
		log.Printf("stream key provider: local")
	}

	liveH := live.NewHandler(liveSvc, sessRepo, cc).
		WithAI(deepseek).
		WithCoupons(cpnRepo).
		WithEvents(liveEventsRepo).
		WithStreamKeyProvider(streamKeyProvider).
		WithAudit(auditRepo).
		WithMuteRepo(muteRepo)
	// LIVESTREAM_API.md endpoint surface: live/start, live/stop, live/my,
	// live/list, live/watch, live/chat/*, live/gifts*, live/gift/send.
	// Replaces the legacy /streams routes (full refactor to the spec).
	liveH.RegisterSpec(router.Group("/api/live"), authMw)

	// SRS webhooks
	srsH := srs.NewHandler(sessRepo).
		WithEvents(bus).
		WithSecret(os.Getenv("SRS_WEBHOOK_SECRET")).
		WithCache(cc)
	if gin.Mode() == gin.ReleaseMode && os.Getenv("SRS_WEBHOOK_SECRET") == "" {
		log.Fatalf("SRS_WEBHOOK_SECRET must be set in release mode (webhook would accept forged on_publish/on_dvr otherwise)")
	}
	srsH.Register(router.Group("/api/srs"))

	// Shops
	shopH := shops.NewHandler(shopRepo)
	shopH.Register(router.Group("/api/shops"), authMw, sellerMw, optAuthMw)

	// Categories
	catH := catalog.NewCategoryHandler(catRepo, cc)
	catH.Register(router.Group("/api/categories"), authMw, adminMw)

	// Products
	prodH := catalog.NewProductHandler(prodRepo,
		catalog.SimpleShopResolver{Lookup: func(ctx context.Context, sellerID uuid.UUID) (uuid.UUID, error) {
			s, err := shopRepo.FindBySellerID(ctx, sellerID)
			if err != nil {
				return uuid.Nil, err
			}
			return s.ID, nil
		}}, cc)
	prodH.Register(router.Group("/api/products"), authMw, sellerMw)

	// Cart
	cartH := commerce.NewCartHandler(cartRepo)
	cartH.Register(router.Group("/api/cart"), authMw)

	// Coupons (buyer-facing: discover platform + shop coupons, validate
	// before checkout). Host coupon CRUD is registered under /api/live by
	// the live handler — these routes are intentionally separate so the
	// public list endpoints stay reachable without seller auth.
	couponH := commerce.NewCouponHandler(cpnRepo)
	couponH.Register(router.Group("/api/coupons"), authMw)

	// Orders
	orderH := commerce.NewOrderHandler(orderSvc, orderRepo)
	orderH.Register(router.Group("/api/orders"), authMw, cc)

	// Payment
	if r2 != nil || true {
		paymentH := payment.NewHandler(orderRepo, orderSvc, momo, vnpay, zalopay, clientURL)
		paymentH.Register(router.Group("/api/payment"), authMw, cc)
	}

	// Upload (only if R2 configured)
	if r2 != nil {
		uploadH := storage.NewUploadHandler(r2, db)
		uploadH.Register(router.Group("/api/upload"), authMw, sellerMw)
	}

	// Background workers used to run inline here as goroutines. They now
	// live in `cmd/worker` so they can be deployed and scaled independently.
	// Run with: `go run ./cmd/worker` (or `make worker`).

	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 60 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		logger.Info("listening", "port", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server: %v", err)
		}
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	<-sigCh
	logger.Info("shutting down")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("shutdown", "err", err)
	}
	logger.Info("bye")
	_ = slog.Default()
}

func getEnvOr(k, fallback string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return fallback
}

// optionalAuth - parse JWT if present but don't require it
func optionalAuth(svc *auth.Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if header == "" {
			c.Next()
			return
		}
		parts := splitBearer(header)
		if parts == "" {
			c.Next()
			return
		}
		claims, err := svc.VerifyAccess(parts)
		if err == nil {
			c.Set("auth.claims", claims)
		}
		c.Next()
	}
}

func splitBearer(h string) string {
	const prefix = "Bearer "
	if len(h) > len(prefix) && h[:len(prefix)] == prefix {
		return h[len(prefix):]
	}
	return ""
}

// authBuyerLookup adapts auth.Repository.FindByID to the minimal
// commerce.BuyerLookup interface (email + name). Lives in main so the
// commerce package stays free of an auth import.
type authBuyerLookup struct{ repo *auth.Repository }

func (a authBuyerLookup) LookupBuyer(ctx context.Context, id uuid.UUID) (commerce.BuyerInfo, error) {
	p, err := a.repo.FindByID(ctx, id)
	if err != nil {
		return commerce.BuyerInfo{}, err
	}
	return commerce.BuyerInfo{Email: p.Email, Name: p.Name}, nil
}
