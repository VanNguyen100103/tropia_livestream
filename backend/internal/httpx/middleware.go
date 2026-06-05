package httpx

import (
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

const HeaderRequestID = "X-Request-ID"
const CtxRequestID = "request_id"

// RequestID middleware - sets X-Request-ID if missing, echoes in response
func RequestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		rid := c.GetHeader(HeaderRequestID)
		if rid == "" {
			rid = uuid.NewString()
		}
		c.Set(CtxRequestID, rid)
		c.Writer.Header().Set(HeaderRequestID, rid)
		c.Next()
	}
}

// SecurityHeaders - helmet-like headers
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		h := c.Writer.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "strict-origin-when-cross-origin")
		h.Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		h.Set("Content-Security-Policy", "default-src 'self'")
		c.Next()
	}
}

// RequestSizeGuard - 413 for non-upload routes > maxKB. skipPrefixes are
// exempted (multipart upload routes that legitimately carry large bodies).
func RequestSizeGuard(maxKB int64, skipPrefixes ...string) gin.HandlerFunc {
	maxBytes := maxKB * 1024
	return func(c *gin.Context) {
		for _, p := range skipPrefixes {
			if p != "" && strings.HasPrefix(c.Request.URL.Path, p) {
				c.Next()
				return
			}
		}
		if c.Request.ContentLength > maxBytes {
			c.AbortWithStatusJSON(http.StatusRequestEntityTooLarge, gin.H{"error": "request too large", "code": "PAYLOAD_TOO_LARGE"})
			return
		}
		c.Next()
	}
}

// ErrorHandler - centralized error response (call ctx.Error(err) and let this convert)
func ErrorHandler(logger *slog.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Next()
		if len(c.Errors) == 0 {
			return
		}
		err := c.Errors.Last().Err
		var ae *AppError
		if errors.As(err, &ae) {
			body := gin.H{"error": ae.Message, "code": ae.Code}
			if ae.Details != nil {
				body["details"] = ae.Details
			}
			if ae.StatusCode >= 500 {
				logger.Error("server error", "request_id", c.GetString(CtxRequestID), "path", c.Request.URL.Path, "err", err)
			}
			c.AbortWithStatusJSON(ae.StatusCode, body)
			return
		}
		logger.Error("unhandled error",
			"request_id", c.GetString(CtxRequestID),
			"path", c.Request.URL.Path,
			"err", err,
		)
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "internal error", "code": "INTERNAL_ERROR"})
	}
}

// AuditLog - structured request log
func AuditLog(logger *slog.Logger) gin.HandlerFunc {
	sensitivePaths := []string{"/api/auth/", "/api/orders", "/api/upload", "/api/payment"}
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		status := c.Writer.Status()
		latency := time.Since(start)

		sensitive := false
		for _, p := range sensitivePaths {
			if strings.HasPrefix(c.Request.URL.Path, p) {
				sensitive = true
				break
			}
		}

		level := slog.LevelDebug
		switch {
		case status >= 500:
			level = slog.LevelError
		case status >= 400:
			level = slog.LevelWarn
		case sensitive:
			level = slog.LevelInfo
		}

		ip := anonymizeIP(c.ClientIP())
		logger.Log(c.Request.Context(), level, "http",
			"request_id", c.GetString(CtxRequestID),
			"method", c.Request.Method,
			"path", c.Request.URL.Path,
			"status", status,
			"latency_ms", latency.Milliseconds(),
			"ip", ip,
			"ua", c.Request.UserAgent(),
		)
	}
}

// anonymizeIP - mask last octet (GDPR-style)
func anonymizeIP(ip string) string {
	if strings.Contains(ip, ".") {
		parts := strings.Split(ip, ".")
		if len(parts) == 4 {
			parts[3] = "0"
			return strings.Join(parts, ".")
		}
	}
	return ip
}

// CleanString - strip null bytes and bidi overrides
func CleanString(s string) string {
	if !utf8.ValidString(s) {
		s = strings.ToValidUTF8(s, "")
	}
	var b strings.Builder
	for _, r := range s {
		switch r {
		case 0, '‮', '‏', '​':
			continue
		}
		b.WriteRune(r)
	}
	return b.String()
}
