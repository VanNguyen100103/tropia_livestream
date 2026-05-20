package main

import (
	"context"
	"errors"
	"log"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/joho/godotenv"

	"github.com/tropia/backend-go/internal/ai"
	"github.com/tropia/backend-go/internal/auth"
	"github.com/tropia/backend-go/internal/cache"
	"github.com/tropia/backend-go/internal/catalog"
	"github.com/tropia/backend-go/internal/commerce"
	"github.com/tropia/backend-go/internal/config"
	"github.com/tropia/backend-go/internal/database"
	"github.com/tropia/backend-go/internal/events"
	"github.com/tropia/backend-go/internal/httpx"
	"github.com/tropia/backend-go/internal/live"
	"github.com/tropia/backend-go/internal/notify"
	"github.com/tropia/backend-go/internal/payment"
	"github.com/tropia/backend-go/internal/shops"
	"github.com/tropia/backend-go/internal/srs"
	"github.com/tropia/backend-go/internal/storage"
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

	emailer := notify.NewEmail(notify.EmailConfig{
		Host:     getEnvOr("EMAIL_HOST", "smtp.gmail.com"),
		Port:     587,
		Username: os.Getenv("EMAIL_USERNAME"),
		Password: os.Getenv("EMAIL_PASSWORD"),
		FromName: getEnvOr("EMAIL_FROM_NAME", "Tropia"),
	})

	deepseek := ai.NewDeepSeek(os.Getenv("DEEPSEEK_API_KEY"))
	_ = deepseek // wire when adding AI endpoints

	// JWT
	jwtSvc := auth.NewService(cfg.JWTAccessSecret, cfg.JWTRefreshSecret, cfg.JWTAccessTTL, cfg.JWTRefreshTTL)

	// Repos
	authRepo := auth.NewRepository(db)
	shopRepo := shops.NewRepository(db)
	catRepo := catalog.NewCategoryRepository(db)
	prodRepo := catalog.NewProductRepository(db)
	sessRepo := live.NewSessionRepository(db)
	cartRepo := commerce.NewCartRepository(db)
	orderRepo := commerce.NewOrderRepository(db)
	cpnRepo := commerce.NewCouponRepository(db)

	// Services
	authSvc := auth.NewAuthService(authRepo, jwtSvc, rds, cc)
	liveSvc := live.NewService(nil, live.ServiceConfig{
		RTMPHost: cfg.SRSRtmpHost,
		HLSHost:  cfg.SRSHlsHost,
		WHIPHost: cfg.SRSWhipHost,
		SRTPort:  10080,
	})
	orderSvc := commerce.NewOrderService(db, orderRepo, cartRepo, cpnRepo, cc)

	// HTTP
	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(httpx.RequestID())
	router.Use(httpx.SecurityHeaders())
	router.Use(httpx.AuditLog(logger))
	router.Use(httpx.ErrorHandler(logger))
	router.Use(httpx.RequestSizeGuard(64, "/api/upload"))
	router.Use(cors.New(cors.Config{
		AllowOrigins:     []string{cfg.CORSOrigin},
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization", "X-Request-ID"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"ok": true, "service": "tropia-backend", "ts": time.Now().Unix()})
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
	authH.Register(router.Group("/api/auth"), authMw)

	googleOAuth := auth.NewGoogleOAuth(authSvc, auth.GoogleOAuthConfig{
		ClientID:     cfg.GoogleClientID,
		ClientSecret: cfg.GoogleClientSecret,
		RedirectURL:  cfg.GoogleRedirectURL,
		DeepLink:     getEnvOr("GOOGLE_APP_DEEP_LINK", "tropia://auth/callback"),
		ClientURL:    clientURL,
	})
	googleOAuth.Register(router.Group("/api/auth"))

	// Live
	liveH := live.NewHandler(liveSvc, sessRepo, cc)
	liveH.Register(router.Group("/api/live"), authMw, sellerMw)

	// AI endpoints (DeepSeek-backed) on top of live sessions
	aiH := live.NewAIHandler(deepseek, sessRepo)
	aiH.Register(router.Group("/api/live"), authMw, sellerMw)

	// SRS webhooks
	srsH := srs.NewHandler(sessRepo)
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

	// Orders
	orderH := commerce.NewOrderHandler(orderSvc, orderRepo)
	orderH.Register(router.Group("/api/orders"), authMw)

	// Payment
	if r2 != nil || true {
		paymentH := payment.NewHandler(orderRepo, momo, vnpay, zalopay, clientURL)
		paymentH.Register(router.Group("/api/payment"), authMw)
	}

	// Upload (only if R2 configured)
	if r2 != nil {
		uploadH := storage.NewUploadHandler(r2)
		uploadH.Register(router.Group("/api/upload"), authMw, sellerMw)
	}

	// Background workers
	go func() {
		bus.Subscribe(ctx, "user.registered", "notify-welcome", "worker-1", func(ctx context.Context, data []byte) error {
			// TODO unmarshal and send welcome
			return nil
		})
	}()
	go func() {
		bus.Subscribe(ctx, "auth.email_otp", "notify-otp", "worker-1", func(ctx context.Context, data []byte) error {
			_ = emailer
			return nil
		})
	}()

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
