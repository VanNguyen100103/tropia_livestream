package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"

	"github.com/tropia/backend-go/internal/auth"
	"github.com/tropia/backend-go/internal/chat"
	"github.com/tropia/backend-go/internal/config"
	"github.com/tropia/backend-go/internal/database"
	"github.com/tropia/backend-go/internal/live"
	"github.com/tropia/backend-go/internal/srs"
)

func main() {
	// Load .env file if present (development convenience)
	for _, f := range []string{".env.development", ".env"} {
		if _, err := os.Stat(f); err == nil {
			if err := godotenv.Load(f); err != nil {
				log.Printf("warning: failed to load %s: %v", f, err)
			} else {
				log.Printf("loaded env from %s", f)
			}
			break
		}
	}

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	gin.SetMode(cfg.GinMode)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Postgres
	db, err := database.NewPostgres(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("postgres: %v", err)
	}
	defer db.Close()
	log.Println("postgres connected")

	// Redis
	rds, err := database.NewRedis(ctx, cfg.RedisAddr, cfg.RedisPassword, cfg.RedisDB)
	if err != nil {
		log.Fatalf("redis: %v", err)
	}
	defer rds.Close()
	log.Println("redis connected")

	// Services
	jwtSvc := auth.NewService(cfg.JWTAccessSecret, cfg.JWTRefreshSecret, cfg.JWTAccessTTL, cfg.JWTRefreshTTL)
	liveRepo := live.NewRepository(db)
	liveSvc := live.NewService(liveRepo, live.ServiceConfig{
		RTMPHost: cfg.SRSRtmpHost,
		HLSHost:  cfg.SRSHlsHost,
		WHIPHost: cfg.SRSWhipHost,
		SRTPort:  10080,
	})

	// HTTP server
	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(gin.Logger())

	router.Use(cors.New(cors.Config{
		AllowOrigins:     []string{cfg.CORSOrigin},
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	authMw := auth.Middleware(jwtSvc)

	api := router.Group("/api")
	{
		auth.NewHandler(db, jwtSvc).Register(api.Group("/auth"), authMw)
		live.NewHandler(liveSvc).Register(api.Group("/live"), authMw)
		chat.NewHandler(db, rds).Register(api.Group("/live"), authMw)
		srs.NewHandler(liveSvc, liveRepo).Register(api.Group("/srs"))
	}

	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Printf("listening on :%s", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server: %v", err)
		}
	}()

	// Graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	<-sigCh
	log.Println("shutting down...")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("shutdown: %v", err)
	}
	log.Println("bye")
}
