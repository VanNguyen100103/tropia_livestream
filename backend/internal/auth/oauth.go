package auth

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/oauth2"
	googleoauth "golang.org/x/oauth2/google"

	"github.com/tropia/backend-go/internal/httpx"
)

type GoogleOAuth struct {
	cfg       *oauth2.Config
	svc       *AuthService
	deepLink  string
	clientURL string
	stateKey  string // arbitrary state validation - in prod use signed cookie or short-lived store
}

type GoogleOAuthConfig struct {
	ClientID     string
	ClientSecret string
	RedirectURL  string
	DeepLink     string
	ClientURL    string
}

func NewGoogleOAuth(svc *AuthService, cfg GoogleOAuthConfig) *GoogleOAuth {
	return &GoogleOAuth{
		cfg: &oauth2.Config{
			ClientID:     cfg.ClientID,
			ClientSecret: cfg.ClientSecret,
			RedirectURL:  cfg.RedirectURL,
			Scopes:       []string{"openid", "email", "profile"},
			Endpoint:     googleoauth.Endpoint,
		},
		svc:       svc,
		deepLink:  cfg.DeepLink,
		clientURL: cfg.ClientURL,
		stateKey:  "tropia-oauth-state",
	}
}

func (g *GoogleOAuth) Register(r *gin.RouterGroup) {
	r.GET("/google", g.start)
	r.GET("/google/callback", g.callback)
}

func (g *GoogleOAuth) start(c *gin.Context) {
	if g.cfg.ClientID == "" {
		c.Error(httpx.NewInternal("google oauth not configured", nil))
		return
	}
	url := g.cfg.AuthCodeURL(g.stateKey, oauth2.AccessTypeOffline)
	c.Redirect(http.StatusFound, url)
}

type googleProfile struct {
	Sub     string `json:"sub"`
	Email   string `json:"email"`
	Name    string `json:"name"`
	Picture string `json:"picture"`
}

func (g *GoogleOAuth) callback(c *gin.Context) {
	if c.Query("state") != g.stateKey {
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

	otc, err := g.svc.StoreOAuthOTC(c.Request.Context(), res.AccessToken, res.RefreshTokenRaw)
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
