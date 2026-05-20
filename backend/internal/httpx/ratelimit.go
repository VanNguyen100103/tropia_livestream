package httpx

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/tropia/backend/internal/cache"
)

type RateLimitConfig struct {
	Limit      int    // max requests
	WindowMs   int64  // window size in milliseconds
	FailClosed bool   // on Redis err: deny (true) or allow (false)
	KeyFunc    func(*gin.Context) string
}

func keyByUserOrIP(c *gin.Context) string {
	if uid, ok := c.Get("user_id"); ok {
		return c.Request.URL.Path + ":u:" + uid.(string)
	}
	return c.Request.URL.Path + ":ip:" + c.ClientIP()
}

func RateLimit(cc *cache.Cache, cfg RateLimitConfig) gin.HandlerFunc {
	if cfg.KeyFunc == nil {
		cfg.KeyFunc = keyByUserOrIP
	}
	return func(c *gin.Context) {
		ok, err := cc.Allow(c.Request.Context(), cfg.KeyFunc(c), cfg.Limit, cfg.WindowMs, cfg.FailClosed)
		if err != nil && cfg.FailClosed {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{"error": "rate limit unavailable", "code": "RATE_LIMITED"})
			return
		}
		if !ok {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{"error": "too many requests", "code": "RATE_LIMITED"})
			return
		}
		c.Next()
	}
}
