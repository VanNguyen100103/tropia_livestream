package auth

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"golang.org/x/oauth2"
	googleoauth "golang.org/x/oauth2/google"

	"github.com/tropia/backend/internal/httpx"
)

const (
	oauthStateTTL    = 5 * time.Minute
	oauthStateBytes  = 32
	oauthStatePrefix = "oauth:state:google:"
)

type GoogleOAuth struct {
	cfg       *oauth2.Config
	svc       *AuthService
	rds       *redis.Client
	deepLink  string
	clientURL string
}

type GoogleOAuthConfig struct {
	ClientID     string
	ClientSecret string
	RedirectURL  string
	DeepLink     string
	ClientURL    string
}

func NewGoogleOAuth(svc *AuthService, rds *redis.Client, cfg GoogleOAuthConfig) *GoogleOAuth {
	return &GoogleOAuth{
		cfg: &oauth2.Config{
			ClientID:     cfg.ClientID,
			ClientSecret: cfg.ClientSecret,
			RedirectURL:  cfg.RedirectURL,
			Scopes:       []string{"openid", "email", "profile"},
			Endpoint:     googleoauth.Endpoint,
		},
		svc:       svc,
		rds:       rds,
		deepLink:  cfg.DeepLink,
		clientURL: cfg.ClientURL,
	}
}

func (g *GoogleOAuth) Register(r *gin.RouterGroup) {
	r.GET("/google", g.start)
	r.GET("/google/callback", g.callback)
}

// newState returns a per-request cryptographically random state token and
// stores it in Redis with a short TTL. The callback validates by atomic
// GETDEL — this gives us single-use CSRF protection without server-side
// session cookies (mobile OAuth has no session cookie to carry state).
//
// challenge is the PKCE S256 code_challenge from the mobile client. When
// present, it is bound to the state entry and propagated to the OTC so
// that ExchangeOTC can verify the matching code_verifier — this prevents
// a hijacking app that intercepted the deep-link callback from spending
// the one-time code.
func (g *GoogleOAuth) newState(ctx context.Context, challenge string) (string, error) {
	b := make([]byte, oauthStateBytes)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	state := hex.EncodeToString(b)
	// We store the challenge directly as the value (or "-" sentinel when
	// the client opted out of PKCE) instead of a JSON blob — keeps Redis
	// allocation small and avoids an unmarshal hop on the callback path.
	val := challenge
	if val == "" {
		val = "-"
	}
	if err := g.rds.Set(ctx, oauthStatePrefix+state, val, oauthStateTTL).Err(); err != nil {
		return "", err
	}
	return state, nil
}

// consumeState atomically removes the state from Redis and returns the
// PKCE challenge that was bound to it (empty when no PKCE was used).
func (g *GoogleOAuth) consumeState(ctx context.Context, state string) (string, bool) {
	if state == "" {
		return "", false
	}
	res, err := g.rds.GetDel(ctx, oauthStatePrefix+state).Result()
	if err != nil || res == "" {
		return "", false
	}
	if res == "-" {
		return "", true
	}
	return res, true
}

func (g *GoogleOAuth) start(c *gin.Context) {
	if g.cfg.ClientID == "" {
		c.Error(httpx.NewInternal("google oauth not configured", nil))
		return
	}
	// RFC 7636 PKCE — mobile client passes S256 code_challenge as a query
	// parameter when opening the auth URL. We only accept the S256 method
	// (plain is unsafe). Length is bounded so an attacker can't pad Redis
	// entries; 43-128 is the spec range for the corresponding verifier.
	challenge := strings.TrimSpace(c.Query("code_challenge"))
	if challenge != "" {
		if len(challenge) < 43 || len(challenge) > 128 || !isBase64URL(challenge) {
			c.Error(httpx.NewValidation("invalid code_challenge", nil))
			return
		}
		if m := c.Query("code_challenge_method"); m != "" && m != "S256" {
			c.Error(httpx.NewValidation("only S256 code_challenge_method is supported", nil))
			return
		}
	}
	state, err := g.newState(c.Request.Context(), challenge)
	if err != nil {
		c.Error(httpx.NewInternal("oauth state", err))
		return
	}
	url := g.cfg.AuthCodeURL(state, oauth2.AccessTypeOffline)
	c.Redirect(http.StatusFound, url)
}

// isBase64URL returns true if s contains only RFC 4648 unpadded base64url
// characters. We use it to gate the PKCE code_challenge before storing.
func isBase64URL(s string) bool {
	for _, r := range s {
		switch {
		case r >= 'A' && r <= 'Z':
		case r >= 'a' && r <= 'z':
		case r >= '0' && r <= '9':
		case r == '-' || r == '_':
		default:
			return false
		}
	}
	return true
}

type googleProfile struct {
	Sub     string `json:"sub"`
	Email   string `json:"email"`
	Name    string `json:"name"`
	Picture string `json:"picture"`
}

func (g *GoogleOAuth) callback(c *gin.Context) {
	challenge, ok := g.consumeState(c.Request.Context(), c.Query("state"))
	if !ok {
		c.Error(httpx.NewAuth("invalid state"))
		return
	}
	code := c.Query("code")
	if code == "" {
		c.Error(httpx.NewValidation("missing code", nil))
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	token, err := g.cfg.Exchange(ctx, code)
	if err != nil {
		c.Error(httpx.NewAuth("oauth exchange failed"))
		return
	}

	prof, err := g.fetchGoogleProfile(ctx, token.AccessToken)
	if err != nil {
		c.Error(httpx.NewInternal("fetch google profile", err))
		return
	}

	res, err := g.svc.LoginOrRegisterGoogle(c.Request.Context(), GoogleUserInfo{
		Email: prof.Email, Name: prof.Name, GoogleID: prof.Sub, AvatarURL: prof.Picture,
	})
	if err != nil {
		c.Error(err)
		return
	}

	otc, err := g.svc.StoreOAuthOTC(c.Request.Context(), res.AccessToken, res.RefreshTokenRaw, challenge)
	if err != nil {
		c.Error(httpx.NewInternal("store otc", err))
		return
	}

	// Redirect to mobile deep-link with OTC
	redirectURL := fmt.Sprintf("%s?code=%s", g.deepLink, otc)
	c.Redirect(http.StatusFound, redirectURL)
}

func (g *GoogleOAuth) fetchGoogleProfile(ctx context.Context, accessToken string) (*googleProfile, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", "https://www.googleapis.com/oauth2/v3/userinfo", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("google userinfo: status %d body %s", resp.StatusCode, body)
	}
	var p googleProfile
	if err := json.NewDecoder(resp.Body).Decode(&p); err != nil {
		return nil, err
	}
	return &p, nil
}
