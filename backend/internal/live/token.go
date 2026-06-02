package live

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/url"
	"strconv"
	"time"
)

// TokenSigner produces short-lived HMAC tokens that gate RTMP publish
// and HLS playback URLs. The infra-side SRS verifies the same HMAC
// with the matching secret before allowing access — without a valid
// token a leaked stream_key is useless.
//
// VERSIONED KEYS (kid). The signer holds a *map* of {kid → secret}
// rather than a single secret so the operator can rotate without
// downtime: stand a new key up, switch `currentKid` to it, leave the
// old key in the map until every token signed under it has expired,
// then remove. The URL carries the `kid` it was signed under so the
// verifier knows which secret to use — this is the same pattern JOSE /
// JWT use with their `kid` header, AWS Signature V4 uses with key
// rotation, and Cloudflare uses for their signed URLs.
//
// Why this matters: a single shared secret is one leak away from
// disaster. Without versioning, rotation is "stop the world": flip
// the secret on both sides, every in-flight token dies, every viewer
// gets a 403 mid-stream. With versioning, rotation overlaps:
// `currentKid` flips, new tokens use the new secret, old tokens
// continue to verify against the old secret until their TTL expires
// naturally. No viewer notices.
//
// FORMAT IS A PLACEHOLDER until the infra team confirms what their
// SRS verification will accept. We currently emit:
//
//   ?kid=<kid>&expire=<unix>&sign=hmac-sha256(path:action:expire:kid, secret_for_kid)
//
// If infra wants different param names, a different payload, or a
// JWT-shaped token, update Sign() in this file — Service.* call sites
// stay the same.
type TokenSigner struct {
	keys       map[string][]byte // kid → secret
	currentKid string            // kid used to sign new tokens
	ttl        time.Duration
	enabled    bool
}

// ErrTokenSignerConfig signals a configuration problem the operator
// must fix — typically a non-empty current kid that isn't in the keys
// map. We deliberately fail loudly (rather than disabling the signer)
// so the operator notices instead of shipping a "secure" build that
// actually signs nothing.
var ErrTokenSignerConfig = errors.New("token signer: invalid key configuration")

// NewTokenSigner constructs a versioned signer.
//
//   keys       — map of kid → secret. Empty / nil disables signing.
//   currentKid — which kid to sign new tokens with. Must exist in keys
//                or the signer disables itself defensively.
//   ttl        — token lifetime. Falls back to 15m on zero.
//
// All callers should prefer NewTokenSignerFromJSON for env wiring;
// this constructor exists for tests and for callers building the map
// in code.
func NewTokenSigner(keys map[string]string, currentKid string, ttl time.Duration) *TokenSigner {
	t := &TokenSigner{}
	if len(keys) == 0 || currentKid == "" {
		return t
	}
	byteKeys := make(map[string][]byte, len(keys))
	for kid, secret := range keys {
		if secret == "" {
			continue
		}
		byteKeys[kid] = []byte(secret)
	}
	if _, ok := byteKeys[currentKid]; !ok {
		// currentKid not in keys — refuse to enable rather than sign
		// with whatever happens to be first in the map.
		return t
	}
	if ttl <= 0 {
		ttl = 15 * time.Minute
	}
	t.keys = byteKeys
	t.currentKid = currentKid
	t.ttl = ttl
	t.enabled = true
	return t
}

// NewTokenSignerFromJSON parses the keys map from a JSON env var.
// Format: '{"v2026-01":"secret-bytes...","v2026-02":"secret-bytes..."}'.
// Empty raw input returns a disabled signer (token signing off).
// Returns the constructed signer plus an error if the JSON is
// malformed — the caller decides whether to fail-fast at boot.
func NewTokenSignerFromJSON(rawJSON, currentKid string, ttl time.Duration) (*TokenSigner, error) {
	if rawJSON == "" {
		return &TokenSigner{}, nil
	}
	var keys map[string]string
	if err := json.Unmarshal([]byte(rawJSON), &keys); err != nil {
		return &TokenSigner{}, err
	}
	t := NewTokenSigner(keys, currentKid, ttl)
	if !t.enabled && len(keys) > 0 && currentKid != "" {
		// User intended to enable signing (provided keys + kid) but
		// the kid wasn't in the map — surface as an error rather than
		// silently leaving signing off.
		return t, ErrTokenSignerConfig
	}
	return t, nil
}

// Enabled reports whether signing is on.
func (t *TokenSigner) Enabled() bool { return t != nil && t.enabled }

// Sign returns the query-string fragment (without leading `?` or `&`)
// to append to the given path. Action is "publish" or "play" — bound
// into the payload so a playback token can't be replayed against the
// publish endpoint. Returns "" when signing is disabled so callers
// can use the same code path with and without the feature.
func (t *TokenSigner) Sign(path, action string) string {
	if !t.Enabled() {
		return ""
	}
	expire := time.Now().Add(t.ttl).Unix()
	secret := t.keys[t.currentKid]
	payload := path + ":" + action + ":" + strconv.FormatInt(expire, 10) + ":" + t.currentKid
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(payload))
	sig := hex.EncodeToString(mac.Sum(nil))
	return "kid=" + url.QueryEscape(t.currentKid) +
		"&expire=" + strconv.FormatInt(expire, 10) +
		"&sign=" + url.QueryEscape(sig)
}

// AppendTo joins the signature onto a URL, inserting `?` or `&` as
// appropriate. Returns the original URL unchanged when signing is
// off — keeps the call sites in service.go branch-free.
func (t *TokenSigner) AppendTo(rawURL, path, action string) string {
	if !t.Enabled() {
		return rawURL
	}
	sep := "?"
	for i := 0; i < len(rawURL); i++ {
		if rawURL[i] == '?' {
			sep = "&"
			break
		}
	}
	return rawURL + sep + t.Sign(path, action)
}

// Verify is intended for an *internal* verification path — if Tropia
// ever needs to verify its own signed URLs (e.g. a debug endpoint or
// integration test). The infra-side SRS does the real verification
// against the same keys map. Returns the kid the token was signed
// with on success so callers can audit which key was in use.
func (t *TokenSigner) Verify(path, action, kid, expireStr, sig string) (string, error) {
	if !t.Enabled() {
		return "", errors.New("signer disabled")
	}
	secret, ok := t.keys[kid]
	if !ok {
		return "", errors.New("unknown kid")
	}
	expire, err := strconv.ParseInt(expireStr, 10, 64)
	if err != nil {
		return "", errors.New("expire not an integer")
	}
	if time.Now().Unix() > expire {
		return "", errors.New("token expired")
	}
	payload := path + ":" + action + ":" + strconv.FormatInt(expire, 10) + ":" + kid
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(payload))
	expected := hex.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(expected), []byte(sig)) {
		return "", errors.New("signature mismatch")
	}
	return kid, nil
}
