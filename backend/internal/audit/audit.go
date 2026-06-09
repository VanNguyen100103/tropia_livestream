// Package audit provides a structured trail for sensitive actions
// (threat 6 — insider threat / post-incident forensics).
//
// Design notes:
//
//   - Append-only. UPDATE / DELETE on audit_log is treated as a bug —
//     if a row turns out to be wrong, insert a corrective row, never
//     mutate.
//
//   - Actor + target are denormalised. We snapshot actor_role and any
//     human-readable fields into payload so the trail still reads
//     correctly after a rename / delete elsewhere in the schema.
//
//   - Failure mode is "warn and continue". A DB hiccup writing the
//     audit row should NOT block the user action that triggered it;
//     we log the failure (so monitoring catches it) but the caller's
//     transaction proceeds. Use Log() in handlers; for atomic audit
//     (must-succeed-with-action), wrap the action + insert in your
//     own transaction.
//
//   - Payload must not contain secrets. The Redactor helper strips
//     known sensitive keys before serialising — callers can lean on
//     it without scrubbing every map by hand.
package audit

import (
	"context"
	"encoding/json"
	"log/slog"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Action names — kept as constants so a typo at the call site is a
// compile error rather than a silent log-line variant nobody can
// search for later. Add new constants when wiring a new audit point;
// avoid raw strings.
const (
	ActionLiveSessionCreate = "live.session.create"
	ActionLiveSessionEnd    = "live.session.end"
	ActionCouponPublish     = "coupon.publish"
	ActionCouponRedeem      = "coupon.redeem"
	ActionChatMute          = "chat.mute"
	ActionChatUnmute        = "chat.unmute"
	ActionChatAutoMute      = "chat.auto_mute"
	ActionStreamKeyIssue    = "stream_key.issue"
	ActionRoleChange        = "user.role_change"
	ActionLoyaltyCredit     = "user.loyalty_credit"
	ActionLoginSuccess      = "auth.login"
	ActionPaymentRefund     = "payment.refund"
)

// Target type names — same rationale.
const (
	TargetLiveSession = "live_session"
	TargetCoupon      = "coupon"
	TargetUser        = "user"
	TargetOrder       = "order"
)

// Repository writes audit rows. One per *pgxpool.Pool; safe to share
// across goroutines (pgxpool handles concurrency).
type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

// Entry captures everything we want to record about one action. All
// fields are optional except Action — Log will silently no-op if
// called with an empty action, on the theory that audit-log code in
// the wrong place is safer than missing audit-log code in the right
// place.
type Entry struct {
	ActorID    *uuid.UUID     // who acted (nil for system / unauthenticated)
	ActorRole  string         // their role at action time
	ActorIP    string         // request IP
	Action     string         // required — one of the Action* constants
	TargetType string         // optional — one of the Target* constants
	TargetID   string         // optional — UUID or other identifier
	Payload    map[string]any // optional — action-specific context (no secrets)
}

// Log persists the entry. Returns nil on success or a logged
// best-effort outcome on failure — the caller does NOT need to
// handle the error in normal flow. Returning the error anyway lets
// tests assert the failure path.
func (r *Repository) Log(ctx context.Context, e Entry) error {
	if e.Action == "" {
		slog.Default().Warn("audit: refused to log empty action")
		return nil
	}
	payloadJSON, err := json.Marshal(Redact(e.Payload))
	if err != nil {
		slog.Default().Warn("audit: payload marshal failed", "action", e.Action, "err", err)
		payloadJSON = []byte(`{}`)
	}
	_, err = r.pool.Exec(ctx, `
		INSERT INTO audit_log (actor_id, actor_role, actor_ip, action, target_type, target_id, payload)
		VALUES ($1, NULLIF($2, ''), NULLIF($3, ''), $4, NULLIF($5, ''), NULLIF($6, ''), $7)
	`,
		e.ActorID, e.ActorRole, e.ActorIP, e.Action, e.TargetType, e.TargetID, payloadJSON,
	)
	if err != nil {
		// Don't propagate — audit failure must not block the user
		// action. But DO log so monitoring sees it; an audit pipeline
		// that's silently dropping rows is worse than no audit.
		slog.Default().Warn("audit: insert failed", "action", e.Action, "err", err)
	}
	return err
}

// redactedKeys is the set of map keys whose values are stripped from
// payloads before serialising. Match is case-insensitive substring on
// the key name — `accessToken`, `STRIPE_API_KEY`, `refresh_token` all
// hit `token`. Add new patterns as they show up in handlers.
var redactedKeys = []string{
	"password", "passwd",
	"secret",
	"token",
	"api_key", "apikey",
	"private_key",
	"hmac",
	"sign",      // signed URL sigs
	"signature",
	"otp",
	"cookie",
}

// Redact returns a shallow copy of m with sensitive-looking values
// replaced by "<redacted>". Nested maps are walked recursively. nil
// inputs return nil so callers can pass payloads through unchanged
// when there's nothing to log.
func Redact(m map[string]any) map[string]any {
	if m == nil {
		return nil
	}
	out := make(map[string]any, len(m))
	for k, v := range m {
		if isSensitiveKey(k) {
			out[k] = "<redacted>"
			continue
		}
		if nested, ok := v.(map[string]any); ok {
			out[k] = Redact(nested)
			continue
		}
		out[k] = v
	}
	return out
}

func isSensitiveKey(k string) bool {
	low := toLower(k)
	for _, pat := range redactedKeys {
		if containsSubstring(low, pat) {
			return true
		}
	}
	return false
}

// toLower / containsSubstring inline-avoid the strings import to keep
// the package's surface small (no dependency on strings means trivial
// to vendor / fork). These cover ASCII only — the redact patterns
// above are all ASCII, so case folding non-ASCII isn't a concern.
func toLower(s string) string {
	b := make([]byte, len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c >= 'A' && c <= 'Z' {
			c += 'a' - 'A'
		}
		b[i] = c
	}
	return string(b)
}

func containsSubstring(haystack, needle string) bool {
	if len(needle) == 0 {
		return true
	}
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}
