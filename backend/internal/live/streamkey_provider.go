package live

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
)

// StreamKeyProvider issues the SRS channel name a host will publish to.
// Two implementations live alongside each other so Tropia can switch
// between them via env without code changes:
//
//   - LocalStreamKeyProvider — Tropia generates the key locally with
//     crypto/rand. Zero coupling to infra. Used in dev and as a
//     fallback when infra is unreachable.
//
//   - InfraStreamKeyProvider — Tropia calls the infra team's stream
//     registry API to obtain a key. Infra knows every key that exists,
//     can revoke any key, and gates SRS publishes against their own
//     registry. Production-grade option but couples our uptime to
//     theirs unless a fallback is configured.
//
// The contract is intentionally narrow (one method) so swapping
// providers later — say, moving to a managed CDN's stream registry —
// only touches main.go wiring.
type StreamKeyProvider interface {
	// Issue returns a stream_key for the given seller. ctx carries
	// timeouts so a slow infra call doesn't block a seller's
	// "Bắt đầu live" tap indefinitely. The TTL hint advises the
	// upstream how long the key should remain valid; implementations
	// may ignore it (local generation has no TTL).
	Issue(ctx context.Context, sellerID uuid.UUID, ttl time.Duration) (string, error)
}

// ─── Local provider ──────────────────────────────────────────────────────────

// LocalStreamKeyProvider produces stream_keys with crypto/rand. The
// 32-byte payload (256 bits) is unguessable in practice; the "live_"
// prefix makes log lines / DB queries scannable. This is the default —
// no external dependencies, no failure modes.
type LocalStreamKeyProvider struct{}

func NewLocalStreamKeyProvider() *LocalStreamKeyProvider {
	return &LocalStreamKeyProvider{}
}

func (p *LocalStreamKeyProvider) Issue(_ context.Context, _ uuid.UUID, _ time.Duration) (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("stream key entropy: %w", err)
	}
	return "live_" + hex.EncodeToString(b), nil
}

// ─── Infra provider ──────────────────────────────────────────────────────────

// ErrInfraProviderUnconfigured signals that the operator wired the
// infra provider but did not set the base URL / API key. We treat this
// as fail-closed: the create handler refuses to start a session rather
// than silently falling back to local generation (which would defeat
// the point of having infra manage keys).
var ErrInfraProviderUnconfigured = errors.New("stream key: infra provider not configured (missing INFRA_STREAM_API_URL or INFRA_STREAM_API_KEY)")

// InfraStreamKeyProvider asks the infra team's stream registry to
// allocate a key. The exact API contract is documented below; once
// infra confirms their endpoint shape we adjust this implementation.
//
// EXPECTED API (subject to confirmation from infra):
//
//   POST <base>/api/v1/streams/issue
//   Headers:
//     Authorization: Bearer <api_key>
//     Content-Type:  application/json
//   Body:
//     { "seller_id": "<uuid>", "ttl_seconds": 14400 }
//   Response 201:
//     { "stream_key": "abc123...", "expires_at": "2026-01-01T00:00:00Z" }
//   Response 4xx/5xx:
//     { "error": "..." }
//
// If infra prefers a different shape (different verb, different field
// names, different auth scheme — mTLS, signed request, HMAC), update
// Issue() accordingly. Keep the contract narrow: Tropia should not
// need to know how infra allocates keys, just that it gets one back.
type InfraStreamKeyProvider struct {
	baseURL string
	apiKey  string
	client  *http.Client
	// fallback is invoked when the infra call fails AND the operator
	// has opted into degraded mode (allowFallback=true). Nil disables
	// fallback — the handler propagates the error and the seller sees
	// "Service unavailable" instead of a stream that infra didn't
	// authorise. Defaults to nil for production safety.
	fallback      StreamKeyProvider
	allowFallback bool
}

// NewInfraStreamKeyProvider wires a client. Both baseURL and apiKey
// must be non-empty or Issue will fail with ErrInfraProviderUnconfigured.
// Pass a non-nil fallback to enable degraded mode — typically a
// LocalStreamKeyProvider so dev/staging continue working when infra is
// down.
func NewInfraStreamKeyProvider(baseURL, apiKey string, fallback StreamKeyProvider, allowFallback bool) *InfraStreamKeyProvider {
	return &InfraStreamKeyProvider{
		baseURL:       strings.TrimRight(baseURL, "/"),
		apiKey:        apiKey,
		client:        &http.Client{Timeout: 5 * time.Second},
		fallback:      fallback,
		allowFallback: allowFallback,
	}
}

type infraIssueRequest struct {
	SellerID   string `json:"seller_id"`
	TTLSeconds int    `json:"ttl_seconds"`
}

type infraIssueResponse struct {
	StreamKey string `json:"stream_key"`
	ExpiresAt string `json:"expires_at,omitempty"`
	Error     string `json:"error,omitempty"`
}

func (p *InfraStreamKeyProvider) Issue(ctx context.Context, sellerID uuid.UUID, ttl time.Duration) (string, error) {
	if p.baseURL == "" || p.apiKey == "" {
		return p.fallbackOrFail(ctx, sellerID, ttl, ErrInfraProviderUnconfigured)
	}
	if ttl <= 0 {
		// 4h matches the upper bound of a Tropia live session in
		// practice (Shopee Live sessions are typically <2h; we err
		// long so a viewer reconnecting near the end still gets a
		// valid key) — adjust once infra confirms their cap.
		ttl = 4 * time.Hour
	}
	payload, err := json.Marshal(infraIssueRequest{
		SellerID:   sellerID.String(),
		TTLSeconds: int(ttl.Seconds()),
	})
	if err != nil {
		return p.fallbackOrFail(ctx, sellerID, ttl, fmt.Errorf("marshal issue: %w", err))
	}
	url := p.baseURL + "/api/v1/streams/issue"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(string(payload)))
	if err != nil {
		return p.fallbackOrFail(ctx, sellerID, ttl, fmt.Errorf("build request: %w", err))
	}
	req.Header.Set("Authorization", "Bearer "+p.apiKey)
	req.Header.Set("Content-Type", "application/json")
	resp, err := p.client.Do(req)
	if err != nil {
		return p.fallbackOrFail(ctx, sellerID, ttl, fmt.Errorf("infra unreachable: %w", err))
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 500 {
		return p.fallbackOrFail(ctx, sellerID, ttl, fmt.Errorf("infra 5xx: %s", strings.TrimSpace(string(body))))
	}
	if resp.StatusCode >= 400 {
		// 4xx is a client/contract problem — fallback would mask the
		// bug. Surface to the operator instead.
		return "", fmt.Errorf("infra rejected issue request (%d): %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	var out infraIssueResponse
	if err := json.Unmarshal(body, &out); err != nil {
		return "", fmt.Errorf("decode infra response: %w", err)
	}
	if out.StreamKey == "" {
		return "", fmt.Errorf("infra returned empty stream_key: %s", out.Error)
	}
	return out.StreamKey, nil
}

func (p *InfraStreamKeyProvider) fallbackOrFail(ctx context.Context, sellerID uuid.UUID, ttl time.Duration, cause error) (string, error) {
	if !p.allowFallback || p.fallback == nil {
		return "", cause
	}
	// We deliberately don't wrap the cause — falling back is the
	// intended path in degraded mode, and the operator already opted
	// in via STREAM_KEY_PROVIDER_FALLBACK=local. Log it for audit so
	// "why did this session get a local key" is answerable.
	return p.fallback.Issue(ctx, sellerID, ttl)
}
