package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"math/big"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"

	"github.com/tropia/backend/internal/cache"
	"github.com/tropia/backend/internal/httpx"
)

const (
	bcryptCost           = 12
	maxFailedLogins      = 5
	lockoutDuration      = 15 * time.Minute
	otpTTL               = 10 * time.Minute
	passwordResetTTL     = 1 * time.Hour
	oauthOTCTTL          = 60 * time.Second
	refreshTokenBytes    = 48
	passwordResetBytes   = 32
)

// EventPublisher is the subset of events.EventBus that AuthService needs.
// Keeping it as an interface avoids an import cycle and makes the service
// trivial to test.
type EventPublisher interface {
	Publish(ctx context.Context, eventType string, payload any) error
}

// noopPublisher is used when no EventBus is wired in (e.g. unit tests).
type noopPublisher struct{}

func (noopPublisher) Publish(context.Context, string, any) error { return nil }

type AuthService struct {
	repo   *Repository
	jwt    *Service
	rds    *redis.Client
	cache  *cache.Cache
	events EventPublisher
}

func NewAuthService(repo *Repository, jwt *Service, rds *redis.Client, c *cache.Cache) *AuthService {
	return &AuthService{repo: repo, jwt: jwt, rds: rds, cache: c, events: noopPublisher{}}
}

// WithEvents wires an EventPublisher so background workers can act on
// register / OTP / password-reset events.
func (s *AuthService) WithEvents(p EventPublisher) *AuthService {
	if p != nil {
		s.events = p
	}
	return s
}

// ---------- Helpers ----------

func sha256Hex(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// generateOTP - 6-digit string (matches Node.js crypto.randomInt(100000, 999999))
func generateOTP() string {
	max := big.NewInt(899999)
	n, _ := rand.Int(rand.Reader, max)
	return fmt.Sprintf("%06d", n.Int64()+100000)
}

func slugify(s string) string {
	s = strings.ToLower(s)
	re := regexp.MustCompile(`[^a-z0-9]+`)
	s = re.ReplaceAllString(s, "-")
	return strings.Trim(s, "-")
}

// ---------- Token issuance ----------

type TokenPair struct {
	AccessToken     string
	RefreshTokenRaw string
	Family          uuid.UUID
	ExpiresAt       time.Time
}

func (s *AuthService) issueTokenPair(ctx context.Context, p *Profile, family *uuid.UUID) (*TokenPair, error) {
	access, err := s.jwt.SignAccess(p.ID.String(), p.Role)
	if err != nil {
		return nil, httpx.NewInternal("sign access token", err)
	}
	refreshRaw := randomHex(refreshTokenBytes)
	refreshHash := sha256Hex(refreshRaw)
	fam := uuid.New()
	if family != nil {
		fam = *family
	}
	expires := time.Now().Add(s.jwt.refreshTTL)
	if err := s.repo.InsertRefreshToken(ctx, p.ID, refreshHash, fam, expires); err != nil {
		return nil, httpx.NewInternal("persist refresh token", err)
	}
	return &TokenPair{AccessToken: access, RefreshTokenRaw: refreshRaw, Family: fam, ExpiresAt: expires}, nil
}

// ---------- Register / OTP ----------

type RegisterInput struct {
	Email    string
	Password string
	Name     string
	Phone    string
	ShopName string
	Role     string
}

type RegisterResult struct {
	User *Profile
	OTP  string
}

// strongPassword: at least 8 chars, with one uppercase and one digit.
// Go regexp does not support lookahead — using manual check.
func strongPassword(pw string) bool {
	if len(pw) < 8 {
		return false
	}
	var hasUpper, hasDigit bool
	for _, r := range pw {
		switch {
		case r >= 'A' && r <= 'Z':
			hasUpper = true
		case r >= '0' && r <= '9':
			hasDigit = true
		}
	}
	return hasUpper && hasDigit
}

// passwordPattern is kept as a shim for callers using MatchString.
var passwordPattern = passwordChecker{}

type passwordChecker struct{}

func (passwordChecker) MatchString(s string) bool { return strongPassword(s) }

func (s *AuthService) Register(ctx context.Context, in RegisterInput) (*RegisterResult, error) {
	in.Email = strings.ToLower(strings.TrimSpace(in.Email))
	in.Name = strings.TrimSpace(in.Name)
	if !passwordPattern.MatchString(in.Password) {
		return nil, httpx.NewValidation("password must be at least 8 chars with uppercase and digit", nil)
	}
	exists, err := s.repo.EmailExists(ctx, in.Email)
	if err != nil {
		return nil, httpx.NewInternal("check email", err)
	}
	if exists {
		return nil, httpx.NewConflict("email already registered")
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(in.Password), bcryptCost)
	if err != nil {
		return nil, httpx.NewInternal("hash password", err)
	}

	// Self-service signup is restricted to buyer/seller. Allowing
	// `role: "admin"` in the request body would let any attacker create
	// an admin account in a single curl — CRITICAL OWASP API3 (Mass
	// Assignment / privilege escalation). Admins must be promoted by
	// another admin via a dedicated internal endpoint (not implemented
	// yet — for now create admins manually in DB).
	role := Role(in.Role)
	if role != RoleSeller {
		role = RoleBuyer
	}

	var phone, shopName *string
	if in.Phone != "" {
		phone = &in.Phone
	}
	if in.ShopName != "" {
		shopName = &in.ShopName
	}

	user, err := s.repo.CreateProfile(ctx, in.Email, string(hash), in.Name, phone, shopName, role)
	if err != nil {
		return nil, httpx.NewInternal("create profile", err)
	}

	// Auto-create shop for seller
	if role == RoleSeller {
		shopDisplayName := in.ShopName
		if shopDisplayName == "" {
			shopDisplayName = in.Name + "'s Shop"
		}
		shopSlug := slugify(shopDisplayName) + "-" + strings.ReplaceAll(user.ID.String(), "-", "")[:8]
		_ = s.repo.CreateShopForSeller(ctx, user.ID, shopDisplayName, shopSlug)
	}

	// Store OTP in Redis
	otp := generateOTP()
	otpKey := "email_otp:" + user.ID.String()
	if err := s.rds.Set(ctx, otpKey, otp, otpTTL).Err(); err != nil {
		return nil, httpx.NewInternal("store otp", err)
	}

	// Publish to worker → sends OTP email
	_ = s.events.Publish(ctx, "auth.email_otp", map[string]any{
		"user_id": user.ID.String(),
		"email":   user.Email,
		"name":    user.Name,
		"otp":     otp,
	})

	return &RegisterResult{User: user, OTP: otp}, nil
}

func (s *AuthService) VerifyEmailOTP(ctx context.Context, email, otp string) error {
	user, err := s.repo.FindByEmail(ctx, strings.ToLower(email))
	if err != nil {
		return httpx.NewNotFound("invalid email or otp")
	}
	if user.EmailVerified {
		return nil // idempotent
	}
	if matched, _ := regexp.MatchString(`^\d{6}$`, otp); !matched {
		return httpx.NewValidation("otp must be 6 digits", nil)
	}
	otpKey := "email_otp:" + user.ID.String()
	stored, err := s.rds.Get(ctx, otpKey).Result()
	if err != nil || stored != otp {
		return httpx.NewValidation("invalid or expired otp", nil)
	}
	s.rds.Del(ctx, otpKey)
	if err := s.repo.MarkEmailVerified(ctx, user.ID); err != nil {
		return httpx.NewInternal("mark verified", err)
	}

	// Publish welcome email (mirrors Node.js: welcome goes out AFTER OTP verify,
	// not after registration).
	_ = s.events.Publish(ctx, "user.registered", map[string]any{
		"user_id": user.ID.String(),
		"email":   user.Email,
		"name":    user.Name,
	})
	return nil
}

func (s *AuthService) ResendOTP(ctx context.Context, email string) (string, error) {
	user, err := s.repo.FindByEmail(ctx, strings.ToLower(email))
	if err != nil || user.EmailVerified {
		// anti-enumeration: silently succeed
		return "", nil
	}
	otp := generateOTP()
	if err := s.rds.Set(ctx, "email_otp:"+user.ID.String(), otp, otpTTL).Err(); err != nil {
		return "", httpx.NewInternal("store otp", err)
	}
	_ = s.events.Publish(ctx, "auth.email_otp", map[string]any{
		"user_id": user.ID.String(),
		"email":   user.Email,
		"name":    user.Name,
		"otp":     otp,
	})
	return otp, nil
}

// ---------- Login ----------

type LoginResult struct {
	User *Profile
	*TokenPair
}

func (s *AuthService) Login(ctx context.Context, email, password string) (*LoginResult, error) {
	user, err := s.repo.FindByEmail(ctx, strings.ToLower(email))
	if err != nil {
		return nil, httpx.NewAuth("invalid credentials")
	}
	return s.completeLogin(ctx, user, password)
}

// LoginByUsername authenticates by either email (when `username` contains
// '@') or phone number — the spec `POST /api/login` passes the user's SĐT
// as `username`.
func (s *AuthService) LoginByUsername(ctx context.Context, username, password string) (*LoginResult, error) {
	username = strings.TrimSpace(username)
	var user *Profile
	var err error
	if strings.Contains(username, "@") {
		user, err = s.repo.FindByEmail(ctx, strings.ToLower(username))
	} else {
		user, err = s.repo.FindByPhone(ctx, username)
	}
	if err != nil {
		return nil, httpx.NewAuth("invalid credentials")
	}
	return s.completeLogin(ctx, user, password)
}

// AccessTTL exposes the access-token lifetime (for the spec `expires`).
func (s *AuthService) AccessTTL() time.Duration { return s.jwt.AccessTTL() }

// completeLogin runs the shared post-lookup checks (status, verification,
// lockout, password) and issues a token pair.
func (s *AuthService) completeLogin(ctx context.Context, user *Profile, password string) (*LoginResult, error) {
	if user.Status != nil && *user.Status == "deleted" {
		return nil, httpx.NewAuth("invalid credentials")
	}
	if !user.EmailVerified {
		return nil, httpx.NewAuth("email not verified")
	}
	if user.LockedUntil != nil && user.LockedUntil.After(time.Now()) {
		return nil, httpx.NewAuth("account locked, try again later")
	}
	if user.PasswordHash == nil {
		return nil, httpx.NewAuth("invalid credentials")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(*user.PasswordHash), []byte(password)); err != nil {
		failed, _ := s.repo.IncrementFailedLogin(ctx, user.ID)
		if failed >= maxFailedLogins {
			_ = s.repo.LockUntil(ctx, user.ID, time.Now().Add(lockoutDuration))
		}
		return nil, httpx.NewAuth("invalid credentials")
	}
	_ = s.repo.ResetLoginCounters(ctx, user.ID)

	pair, err := s.issueTokenPair(ctx, user, nil)
	if err != nil {
		return nil, err
	}
	return &LoginResult{User: user, TokenPair: pair}, nil
}

// ---------- Refresh (rotation + reuse detection) ----------

func (s *AuthService) Refresh(ctx context.Context, rawToken string) (*TokenPair, error) {
	tokenHash := sha256Hex(rawToken)
	stored, err := s.repo.FindRefreshToken(ctx, tokenHash)
	if err != nil {
		return nil, httpx.NewAuth("invalid refresh token")
	}
	now := time.Now()
	if stored.Revoked || stored.ExpiresAt.Before(now) {
		// Reuse attack: revoke entire family
		_ = s.repo.RevokeFamily(ctx, stored.Family)
		return nil, httpx.NewAuth("refresh token reuse detected")
	}
	user, err := s.repo.FindByID(ctx, stored.UserID)
	if err != nil {
		return nil, httpx.NewAuth("user not found")
	}
	// Revoke used token, rotate
	_ = s.repo.RevokeRefreshToken(ctx, tokenHash)
	return s.issueTokenPair(ctx, user, &stored.Family)
}

func (s *AuthService) Logout(ctx context.Context, rawToken string) error {
	if rawToken == "" {
		return nil
	}
	return s.repo.RevokeRefreshToken(ctx, sha256Hex(rawToken))
}

func (s *AuthService) LogoutAll(ctx context.Context, userID uuid.UUID) error {
	return s.repo.RevokeAllForUser(ctx, userID)
}

// ---------- Password reset ----------

func (s *AuthService) ForgotPassword(ctx context.Context, email string) (string, error) {
	user, err := s.repo.FindByEmail(ctx, strings.ToLower(email))
	if err != nil {
		return "", nil // anti-enumeration
	}
	rawToken := randomHex(passwordResetBytes)
	hash := sha256Hex(rawToken)
	expires := time.Now().Add(passwordResetTTL)
	if err := s.repo.SetPasswordReset(ctx, user.ID, hash, expires); err != nil {
		return "", httpx.NewInternal("set reset token", err)
	}
	_ = s.events.Publish(ctx, "auth.password_reset", map[string]any{
		"user_id":     user.ID.String(),
		"email":       user.Email,
		"name":        user.Name,
		"reset_token": rawToken, // worker builds reset URL from this
	})
	return rawToken, nil
}

func (s *AuthService) ResetPassword(ctx context.Context, rawToken, newPassword string) error {
	if !passwordPattern.MatchString(newPassword) {
		return httpx.NewValidation("password too weak", nil)
	}
	user, err := s.repo.FindByPasswordResetToken(ctx, sha256Hex(rawToken))
	if err != nil {
		return httpx.NewAuth("invalid or expired reset token")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcryptCost)
	if err != nil {
		return httpx.NewInternal("hash password", err)
	}
	if err := s.repo.UpdatePassword(ctx, user.ID, string(hash)); err != nil {
		return httpx.NewInternal("update password", err)
	}
	_ = s.repo.RevokeAllForUser(ctx, user.ID)
	return nil
}

// ---------- Google OAuth ----------

type GoogleUserInfo struct {
	Email     string
	Name      string
	GoogleID  string
	AvatarURL string
}

// LoginOrRegisterGoogle - finds user by email, refreshes google_id; creates if missing.
func (s *AuthService) LoginOrRegisterGoogle(ctx context.Context, info GoogleUserInfo) (*LoginResult, error) {
	user, err := s.repo.FindByEmail(ctx, strings.ToLower(info.Email))
	if err != nil {
		// New Google user
		user, err = s.repo.CreateGoogleProfile(ctx, strings.ToLower(info.Email), info.Name, info.GoogleID, info.AvatarURL)
		if err != nil {
			return nil, httpx.NewInternal("create google profile", err)
		}
	} else {
		if user.Status != nil && *user.Status == "deleted" {
			return nil, httpx.NewAuth("account deactivated")
		}
		// Patch google_id / avatar if missing
		_ = s.repo.UpdateGoogleID(ctx, user.ID, info.GoogleID, info.AvatarURL)
	}
	pair, err := s.issueTokenPair(ctx, user, nil)
	if err != nil {
		return nil, err
	}
	return &LoginResult{User: user, TokenPair: pair}, nil
}

// StoreOAuthOTC stores a one-time code for deep-link exchange. challenge
// is the PKCE code_challenge that was bound to the OAuth state; pass ""
// for legacy clients that opted out of PKCE.
func (s *AuthService) StoreOAuthOTC(ctx context.Context, accessToken, refreshToken, challenge string) (string, error) {
	code := randomHex(24)
	payload, err := jsonMarshalOTC(otcPayload{
		Access:    accessToken,
		Refresh:   refreshToken,
		Challenge: challenge,
	})
	if err != nil {
		return "", err
	}
	if err := s.rds.Set(ctx, "oauth:otc:"+code, payload, oauthOTCTTL).Err(); err != nil {
		return "", err
	}
	return code, nil
}

// ExchangeOTC trades the one-time code for the JWT pair. When the OTC was
// minted with a PKCE challenge, verifier must satisfy
// BASE64URL(SHA256(verifier)) == challenge — otherwise an attacker who
// hijacked the deep-link callback (e.g. via a competing app registered
// for tropia://auth/callback) cannot spend the code.
func (s *AuthService) ExchangeOTC(ctx context.Context, code, verifier string) (accessToken, refreshToken string, err error) {
	key := "oauth:otc:" + code
	val, err := s.rds.GetDel(ctx, key).Result() // single-use, atomic
	if err != nil {
		return "", "", httpx.NewAuth("invalid or expired code")
	}
	var data otcPayload
	if err := jsonUnmarshal(val, &data); err != nil {
		return "", "", httpx.NewInternal("parse otc", err)
	}
	if data.Challenge != "" {
		if !verifyPKCE(verifier, data.Challenge) {
			return "", "", httpx.NewAuth("invalid code_verifier")
		}
	}
	return data.Access, data.Refresh, nil
}

type otcPayload struct {
	Access    string `json:"access_token"`
	Refresh   string `json:"refresh_token"`
	Challenge string `json:"challenge,omitempty"`
}

func jsonMarshalOTC(p otcPayload) (string, error) {
	b, err := jsonMarshal(p)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// verifyPKCE returns true iff BASE64URL(SHA256(verifier)) == challenge.
// Uses a constant-time comparison so timing differences don't reveal
// partial-match information.
func verifyPKCE(verifier, challenge string) bool {
	if len(verifier) < 43 || len(verifier) > 128 {
		return false
	}
	sum := sha256.Sum256([]byte(verifier))
	got := base64URLEncodeNoPad(sum[:])
	return constantTimeStringEq(got, challenge)
}
