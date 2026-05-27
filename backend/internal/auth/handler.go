package auth

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/tropia/backend/internal/cache"
	"github.com/tropia/backend/internal/httpx"
)

type Handler struct {
	svc        *AuthService
	deepLink   string
	clientURL  string
	cookieSecure bool
}

// devOnly returns the secret (OTP, reset token) only when running outside
// release mode. In production the email worker is the sole channel that
// gets these — exposing them in the API response let any caller with the
// victim's email do an account takeover (CRITICAL: P0 security hole).
func devOnly(secret string) string {
	if gin.Mode() == gin.ReleaseMode {
		return ""
	}
	return secret
}

type HandlerConfig struct {
	GoogleAppDeepLink string
	ClientURL         string
	CookieSecure      bool
}

func NewAPIHandler(svc *AuthService, cfg HandlerConfig) *Handler {
	deepLink := cfg.GoogleAppDeepLink
	if deepLink == "" {
		deepLink = "tropia://auth/callback"
	}
	return &Handler{svc: svc, deepLink: deepLink, clientURL: cfg.ClientURL, cookieSecure: cfg.CookieSecure}
}

func (h *Handler) Register(r *gin.RouterGroup, authMw gin.HandlerFunc, cc *cache.Cache) {
	// Rate limits per-route. KeyFunc defaults to (path + IP) for anon
	// endpoints, which is what we want for brute-force protection. Limits
	// are sliding-window via Redis Lua (see cache.Allow), so a burst of
	// requests immediately after the window opens still gets throttled.
	// fail-closed = true → if Redis is down the API rejects auth attempts
	// instead of falling open (safer default for a sign-in surface).
	loginLimit := httpx.RateLimit(cc, httpx.RateLimitConfig{
		Limit: 5, WindowMs: 60 * 1000, FailClosed: true,
	})
	registerLimit := httpx.RateLimit(cc, httpx.RateLimitConfig{
		Limit: 3, WindowMs: 5 * 60 * 1000, FailClosed: true,
	})
	otpLimit := httpx.RateLimit(cc, httpx.RateLimitConfig{
		Limit: 3, WindowMs: 60 * 1000, FailClosed: true,
	})
	forgotLimit := httpx.RateLimit(cc, httpx.RateLimitConfig{
		Limit: 3, WindowMs: 15 * 60 * 1000, FailClosed: true,
	})

	r.POST("/register", registerLimit, h.register)
	r.POST("/login", loginLimit, h.login)
	r.POST("/refresh", h.refresh)
	r.POST("/logout", h.logout)
	r.POST("/verify-otp", otpLimit, h.verifyOTP)
	r.POST("/resend-verify-email", otpLimit, h.resendOTP)
	r.POST("/forgot-password", forgotLimit, h.forgotPassword)
	r.POST("/reset-password", otpLimit, h.resetPassword)
	r.GET("/google/exchange", h.googleExchange)

	// authed
	authed := r.Group("/", authMw)
	authed.POST("/logout-all", h.logoutAll)
	authed.GET("/me", h.me)
}

// ---------- helpers ----------

func (h *Handler) setRefreshCookie(c *gin.Context, raw string, expires time.Time) {
	maxAge := int(time.Until(expires).Seconds())
	if maxAge < 0 {
		maxAge = 0
	}
	c.SetSameSite(http.SameSiteStrictMode)
	c.SetCookie("refresh_token", raw, maxAge, "/api/auth", "", h.cookieSecure, true)
}

func (h *Handler) clearRefreshCookie(c *gin.Context) {
	c.SetSameSite(http.SameSiteStrictMode)
	c.SetCookie("refresh_token", "", -1, "/api/auth", "", h.cookieSecure, true)
}

func userToJSON(u *Profile) gin.H {
	out := gin.H{
		"id":            u.ID,
		"email":         u.Email,
		"name":          u.Name,
		"role":          u.Role,
		"email_verified": u.EmailVerified,
		"created_at":    u.CreatedAt,
	}
	if u.AvatarURL != nil {
		out["avatar_url"] = *u.AvatarURL
	}
	if u.Phone != nil {
		out["phone"] = *u.Phone
	}
	return out
}

// ---------- Endpoints ----------

type registerReq struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=8,max=72"`
	Name     string `json:"name" binding:"required,min=1,max=100"`
	Phone    string `json:"phone"`
	ShopName string `json:"shop_name"`
	Role     string `json:"role"`
}

func (h *Handler) register(c *gin.Context) {
	var req registerReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	res, err := h.svc.Register(c.Request.Context(), RegisterInput{
		Email: req.Email, Password: req.Password, Name: req.Name,
		Phone: req.Phone, ShopName: req.ShopName, Role: req.Role,
	})
	if err != nil {
		c.Error(err)
		return
	}
	resp := gin.H{"user": userToJSON(res.User)}
	if otp := devOnly(res.OTP); otp != "" {
		resp["otp_dev"] = otp
	}
	c.JSON(http.StatusCreated, resp)
}

type loginReq struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

func (h *Handler) login(c *gin.Context) {
	var req loginReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	res, err := h.svc.Login(c.Request.Context(), req.Email, req.Password)
	if err != nil {
		c.Error(err)
		return
	}
	h.setRefreshCookie(c, res.RefreshTokenRaw, res.ExpiresAt)
	c.JSON(http.StatusOK, gin.H{
		"access_token":  res.AccessToken,
		"refresh_token": res.RefreshTokenRaw, // also returned for mobile apps that can't use cookies
		"user":          userToJSON(res.User),
	})
}

func (h *Handler) refresh(c *gin.Context) {
	raw, _ := c.Cookie("refresh_token")
	if raw == "" {
		var body struct {
			RefreshToken string `json:"refresh_token"`
		}
		_ = c.ShouldBindJSON(&body)
		raw = body.RefreshToken
	}
	if raw == "" {
		c.Error(httpx.NewAuth("missing refresh token"))
		return
	}
	pair, err := h.svc.Refresh(c.Request.Context(), raw)
	if err != nil {
		h.clearRefreshCookie(c)
		c.Error(err)
		return
	}
	h.setRefreshCookie(c, pair.RefreshTokenRaw, pair.ExpiresAt)
	c.JSON(http.StatusOK, gin.H{
		"access_token":  pair.AccessToken,
		"refresh_token": pair.RefreshTokenRaw,
	})
}

func (h *Handler) logout(c *gin.Context) {
	raw, _ := c.Cookie("refresh_token")
	_ = h.svc.Logout(c.Request.Context(), raw)
	h.clearRefreshCookie(c)
	c.Status(http.StatusNoContent)
}

func (h *Handler) logoutAll(c *gin.Context) {
	claims, _ := ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	_ = h.svc.LogoutAll(c.Request.Context(), uid)
	h.clearRefreshCookie(c)
	c.Status(http.StatusNoContent)
}

func (h *Handler) me(c *gin.Context) {
	claims, _ := ClaimsFrom(c)
	uid, err := uuid.Parse(claims.UserID)
	if err != nil {
		c.Error(httpx.NewAuth("invalid token"))
		return
	}
	user, err := h.svc.repo.FindByID(c.Request.Context(), uid)
	if err != nil {
		c.Error(httpx.NewNotFound("user not found"))
		return
	}
	c.JSON(http.StatusOK, userToJSON(user))
}

type otpReq struct {
	Email string `json:"email" binding:"required,email"`
	OTP   string `json:"otp" binding:"required,len=6"`
}

func (h *Handler) verifyOTP(c *gin.Context) {
	var req otpReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	if err := h.svc.VerifyEmailOTP(c.Request.Context(), req.Email, req.OTP); err != nil {
		c.Error(err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "email verified"})
}

type emailReq struct {
	Email string `json:"email" binding:"required,email"`
}

func (h *Handler) resendOTP(c *gin.Context) {
	var req emailReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	otp, err := h.svc.ResendOTP(c.Request.Context(), req.Email)
	if err != nil {
		c.Error(err)
		return
	}
	resp := gin.H{"message": "if account exists, an otp was sent"}
	if otpDev := devOnly(otp); otpDev != "" {
		resp["otp_dev"] = otpDev
	}
	c.JSON(http.StatusOK, resp)
}

func (h *Handler) forgotPassword(c *gin.Context) {
	var req emailReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	token, err := h.svc.ForgotPassword(c.Request.Context(), req.Email)
	if err != nil {
		c.Error(err)
		return
	}
	resp := gin.H{"message": "if account exists, reset link was sent"}
	if tokenDev := devOnly(token); tokenDev != "" {
		resp["reset_token_dev"] = tokenDev
	}
	c.JSON(http.StatusOK, resp)
}

type resetReq struct {
	Token       string `json:"token" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=8"`
}

func (h *Handler) resetPassword(c *gin.Context) {
	var req resetReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	if err := h.svc.ResetPassword(c.Request.Context(), req.Token, req.NewPassword); err != nil {
		c.Error(err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "password updated"})
}

// ---------- Google OAuth ----------

// /api/auth/google -> redirects to Google
// (Implemented in oauth.go)

// /api/auth/google/exchange?code=XXX[&code_verifier=YYY] -> deep-link exchange.
// code_verifier is required iff the mobile client passed a code_challenge
// when opening /api/auth/google (PKCE — RFC 7636).
func (h *Handler) googleExchange(c *gin.Context) {
	code := strings.TrimSpace(c.Query("code"))
	if code == "" {
		c.Error(httpx.NewValidation("missing code", nil))
		return
	}
	verifier := strings.TrimSpace(c.Query("code_verifier"))
	access, refresh, err := h.svc.ExchangeOTC(c.Request.Context(), code, verifier)
	if err != nil {
		c.Error(err)
		return
	}
	h.setRefreshCookie(c, refresh, time.Now().Add(h.svc.jwt.refreshTTL))
	c.JSON(http.StatusOK, gin.H{"access_token": access, "refresh_token": refresh})
}
