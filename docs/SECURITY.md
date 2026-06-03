# Tropia — Security Posture

Single source of truth for the threat model behind the live-shopping
platform, what we've shipped, and what's still on the runway. Read this
before touching the streaming, payment, or chat paths.

## Threat model

| # | Threat | Hậu quả | Likelihood |
|---|---|---|---|
| 1 | **Stream hijack** — attacker pushes to a victim's stream_key | Buyer sees fake video / scam / brand-damaging content | High (no token: 1-click; with token: requires sniff or malware) |
| 2 | **Leeching** — third-party site embeds our HLS | Lost traffic + analytics, can't enforce ToS | High |
| 3 | **Recording + reupload** — viewer screen-records or DVR's HLS, posts elsewhere | KOL exclusive content copied, lost ad value | Medium |
| 4 | **DDoS publisher endpoint** | Seller can't push, livestream dies | Medium |
| 5 | **Token theft + replay** | Within TTL window attacker can act as seller/viewer | Low (needs MITM or malware) |
| 6 | **Insider threat** — DB or secret leak | Catastrophic — all stream_keys / publish creds exposed | Low but catastrophic |
| 7 | **DB scraping** — bot enumerates `/api/live/streams` | Fake view counts, harvested seller list for spam | High |
| 8 | **Coupon abuse / flash-sale gaming** — concurrent redemption past max_uses | Direct $ loss on promotions | High |
| 9 | **Chat manipulation** — spam, scam links, off-platform payment | Trust collapse, platform liability | High |

## Current defenses

| # | Threat | Status | Mechanism (file:line) |
|---|---|---|---|
| 1 | Stream hijack | ✅ | `stream_key` is 32 bytes crypto-random ([handler.go](../backend/internal/live/handler.go)); only returned to owner; duplicate-publisher gate via Redis SET NX in `on_publish` ([webhook.go:127-160](../backend/internal/srs/webhook.go#L127-L160)); HLS proxy hides the key from the viewer URL entirely ([hls_proxy.go](../backend/internal/live/hls_proxy.go)); versioned HMAC token signer ready ([token.go](../backend/internal/live/token.go)) — enable once infra ships matching kid map |
| 2 | Leeching | ✅ | HLS proxy means the bare SRS path is never exposed — embedding from a third-party site requires Tropia's proxy origin, which CORS-locks to whitelisted domains; signed-URL versioned skeleton augments this once enabled |
| 3 | Recording + reupload | ✅ | Chat baked into VOD as subtitles ([bake.go](../backend/internal/vod/bake.go)); forensic watermark `TROPIA · <session_id>` drawn bottom-right via FFmpeg `drawtext` — surfaces session id even on reuploads |
| 4 | DDoS publisher | ✅ | `POST /streams` per-seller 10/hour; `POST /like` 60/min/IP; `POST /chat` 30/min/user; `GET /streams` 120/min/IP — all via the sliding-window Redis limiter ([handler.go](../backend/internal/live/handler.go)) |
| 5 | Token theft + replay | ✅ | JWT 15m TTL ([config.go](../backend/internal/config/config.go)); TLS enforced on prod Postgres; versioned HMAC signer (`kid` rotation, zero-downtime) ready ([token.go](../backend/internal/live/token.go)); 15m signing TTL via `SRS_TOKEN_TTL` |
| 6 | Insider threat | ✅ | Secrets in env only; `stream_key` never logged; webhook secret constant-time compare; **`audit_log` table** ([migration 0002](../backend/migrations/0002_audit_log_and_chat_mutes.up.sql)) + `internal/audit` package — every sensitive action (live create/end, coupon publish, chat mute, role change) emits a row with actor / IP / payload (auto-redacted for token / secret keys) |
| 7 | DB scraping | ✅ | `GET /streams` rate-limited 120/min/IP + 3s cache + **600-req/10-min long-window scraper detection** with audit row on trip ([handler.go:listActive](../backend/internal/live/handler.go)); **cursor pagination** (started_at, id) replaces offset so the endpoint can't be enumerated past the rate limit ([session_repo.go:ListActiveCursor](../backend/internal/live/session_repo.go)) |
| 8 | Coupon abuse | ✅ | Server-side validation; `UNIQUE (coupon_id, user_id)` prevents per-user double-claim; `RecordUsage` does atomic `UPDATE ... WHERE used_count < max_uses` so the `max_uses` race is closed at the DB layer; structured audit log on every redemption ([coupons.go](../backend/internal/commerce/coupons.go)) |
| 9 | Chat manipulation | ✅ | Per-user rate limit 30/min; URL regex masks links from non-host (`[link bị chặn]`); 13-phrase scam blocklist rejects + auto-mutes outright ([chat_filter.go](../backend/internal/live/chat_filter.go)); **host mute/unmute endpoints** with audit ([handler.go:muteChatUser](../backend/internal/live/handler.go)); **auto-mute on filter hit** + **burst-rate auto-mute** (3 masked-URL hits in 5 min → 5-min timeout) via Redis sliding window ([handler.go:autoMuteIfBurst](../backend/internal/live/handler.go)) |

## Blocked on infra

These need the SRS infra team to coordinate before we can finish:

1. **Versioned HMAC keys** — operator owns `SRS_TOKEN_KEYS_JSON` (a `{kid → secret}` map). Infra-side SRS must verify each incoming token against the secret matching the URL's `kid` param, NOT a hardcoded single secret. See "Token signing — versioned HMAC" below.
2. **HTTPS for HLS + API** (Let's Encrypt cert on the SRS host) — without it the token in URLs leaks over the wire to anyone on the same Wi-Fi.
3. **RTMPS for publish** (port 443 or 1936 with TLS) — same threat model: plaintext RTMP leaks the publish token.
4. **Webhook secret** in production — needed once the backend is publicly reachable so `on_publish`/`on_unpublish`/`on_dvr` can be authenticated.
5. **(Optional) Stream key registry** — only needed if infra wants to be the source-of-truth for stream_keys. Default architecture is **Tropia generates locally + HMAC token gates access**, which already gives infra full revocation power via key rotation. See "Stream key provider contract" below for the optional registry-based mode.

## Token signing — versioned HMAC

Why versioned (not single-secret):

A shared HMAC secret has one fatal property — when it leaks, EVERYTHING signed with it becomes forgeable, AND rotating it kicks every in-flight stream off because their existing tokens stop verifying.

Versioned keys (the JOSE / JWT `kid` pattern, also used by Akamai EdgeAuth, AWS Sig V4, Cloudflare signed URLs) fix this:

- Tropia and infra both hold a *map* of `{kid → secret}` rather than one secret.
- Every signed URL carries the `kid` it was signed under: `?kid=v2026-02&expire=...&sign=...`.
- Verifier looks up `kid` in the map → uses that secret → verifies.

URL format (placeholder — confirm with infra):

```
rtmp://srs/live/<stream_key>?kid=v2026-02&expire=1717050000&sign=<hex>

sign = HMAC_SHA256(
  <path>:<action>:<expire>:<kid>,
  secret_for_kid
)

action ∈ { "publish", "play" }    # binds intent so play-token ≠ publish-token
path   = "/live/<stream_key>"      # full request path, no host
expire = Unix seconds
kid    = the version label
```

### Rotation procedure (zero downtime)

When a secret leaks (or every 90 days, whichever comes first):

1. Generate a new secret: `openssl rand -hex 32` → call it `v2026-03`.
2. **Both** Tropia and infra append `v2026-03` to their key maps. Old keys (`v2026-01`, `v2026-02`) stay.
3. Tropia flips `SRS_TOKEN_CURRENT_KID=v2026-03` and restarts the API. New tokens sign under v2026-03. Old tokens already issued continue to verify because their `kid` is still in the map.
4. Wait one TTL (`SRS_TOKEN_TTL`, default 15 minutes) so every token signed under the leaked kid has expired naturally.
5. **Both** sides remove the leaked kid from their maps. The verifier now rejects any further attempt to use it.

Throughout this procedure no viewer or publisher sees an error — the rolling overlap of valid kids absorbs the rotation.

### What infra needs to implement on their side

- Parse `kid` from the URL query string.
- Maintain `{kid → secret}` map (matching Tropia's).
- HMAC-SHA256 verify with the secret matching that `kid`.
- Reject tokens where `kid` is not in the map (unknown / expired key).
- Reject tokens where `now() > expire`.

If infra prefers JWT shape instead, see commentary in [token.go](../backend/internal/live/token.go) — Tropia can emit either.

See `docs/INFRA-QUESTIONS.md` (or the latest Zalo thread) for the exact wording to ask.

See `docs/INFRA-QUESTIONS.md` (or the latest Zalo thread) for the exact wording to ask.

## Stream key provider contract

Tropia can run with either a **local** key generator (current default — `crypto/rand` inside the API binary) or an **infra-managed** registry where the infra team is the source of truth for every stream_key in flight.

Toggle is one env var:

```
STREAM_KEY_PROVIDER=local        # default — Tropia self-serves keys
STREAM_KEY_PROVIDER=infra        # Tropia delegates to the infra registry
INFRA_STREAM_API_URL=https://media-control.infra.example
INFRA_STREAM_API_KEY=<bearer>
STREAM_KEY_PROVIDER_ALLOW_FALLBACK=false  # true allows local fallback on infra outage
```

### Why use the infra provider?

- **Infra has the audit trail.** Every stream_key allocated is recorded on their side; correlation with the SRS publish/play traffic doesn't depend on Tropia's logs.
- **Infra can kill switch.** A compromised seller account or a known-bad stream can be revoked from the registry without a Tropia deploy.
- **No more shared-secret blast radius.** With a registry, leaking the *signing* secret doesn't grant publish — the registry has to have issued the key first.

### When to stay on local

- Dev / CI / demo environments where infra isn't deployed.
- Disaster fallback when the registry is being migrated and you've explicitly accepted the reduced-security stance for the window (set `STREAM_KEY_PROVIDER_ALLOW_FALLBACK=true`).

### API contract Tropia expects from infra

The skeleton in [streamkey_provider.go](../backend/internal/live/streamkey_provider.go) targets this shape — adjust both ends together if the infra team prefers different verbs / field names.

```
POST <INFRA_STREAM_API_URL>/api/v1/streams/issue
Headers:
  Authorization: Bearer <INFRA_STREAM_API_KEY>
  Content-Type:  application/json
Body:
  { "seller_id": "<uuid>", "ttl_seconds": 14400 }
Response 201 (created):
  { "stream_key": "<infra-allocated string>", "expires_at": "<RFC3339>" }
Response 4xx / 5xx:
  { "error": "<human readable>" }
```

Optional companion endpoints we'd like (not strictly required for MVP):

```
DELETE /api/v1/streams/<key>             # revoke key (kill switch)
GET    /api/v1/streams/<key>             # current state, TTL remaining
GET    /api/v1/streams?seller_id=<uuid>  # list active keys per seller
```

### Failure modes

| Scenario | Tropia behaviour |
|---|---|
| Infra returns 201 with key | Use it. |
| Infra returns 4xx | Surface 5xx to seller. Don't fallback — likely a contract bug, masking it is worse. |
| Infra returns 5xx / unreachable | Fail closed by default. With `STREAM_KEY_PROVIDER_ALLOW_FALLBACK=true`, falls back to local generator and logs a structured warning. |
| Infra config missing (URL / key empty) | Refuse to issue (`ErrInfraProviderUnconfigured`). Operator typo shouldn't silently degrade. |

## Roadmap

### Sprint 1 — landed (this PR)
- 32-byte stream_key
- Rate limits on `/streams` create + list
- Anti-duplicate publisher gate
- Chat URL filter + scam blocklist
- VOD forensic watermark
- Coupon `max_uses` race fix + audit logging
- Versioned HMAC token signer (kid rotation, off by default)
- HLS proxy — `stream_key` hidden from viewer URLs
- Stream key provider abstraction (local + infra-registry option)
- **`audit_log` table** + `internal/audit` package wired into create/end/coupon/mute
- **Chat moderation**: host mute/unmute endpoints + auto-mute on filter hit + burst-rate auto-mute
- **Cursor pagination** on `GET /streams` (started_at, id tuple)
- **Long-window scraper detection** — 600 req / 10 min / IP triggers 429 + audit row

### Sprint 2 — when infra unblocks
- Wire `SRS_TOKEN_SECRET` — set env on both Tropia + SRS, flip on
- Validate token format with infra against a staging push/pull cycle
- HTTPS for the API + HLS host
- RTMPS for publish — Flutter publisher needs `librtmps` or platform native
- Webhook reachability over HTTPS + real secret

### Sprint 3 — production hardening
- Separate `publish_key` and `playback_key` (DB migration + SRS forward rule). Defence-in-depth: even if a playback token leaks, it can't be replayed against RTMP.
- Per-viewer token rotation over the existing WebSocket (signal new URL every ~5 min; player swaps `.m3u8`)
- Host mute / shadow-ban endpoints; moderation queue
- General `audit_log` table — sensitive action events with actor / target / payload / IP

### Sprint 4 — scale / premium
- Migrate viewer-facing HLS to a managed CDN with native signed URLs (Cloudflare Stream / AWS IVS / Mux)
- DRM (Widevine + FairPlay) for KOL-exclusive sessions
- Edge fingerprinting (bot vs human) on `GET /streams`
- DB column encryption at rest for PII fields

## What's explicitly out of scope

- **Preventing screen-recording on the viewer's device.** OS-level capture (DroidCast, ScreenStream, OBS Display Capture) defeats any DRM short of HDCP-enforced playback, and even that fails at the lens. We rely on watermarking + ToS + takedown instead.
- **Stopping a determined attacker who has compromised the seller's phone.** Threat model treats the seller's device as a trusted boundary. Token rotation limits the damage but doesn't prevent it.
- **Hiding `stream_key` from viewers entirely.** Standard SRS routes by path so the key is in the HLS URL. Closing that gap requires a backend proxy (~3-5 days dev + bandwidth cost x N viewers) — deferred to Sprint 4. Token signing makes the leaked key harmless in the meantime.

## Reporting a vulnerability

Email `security@tropia.vn` (or `nganhvan1609@gmail.com` in early stages).
Please don't open public GitHub issues for security bugs.

## Verifying these defenses

Each fix above lives behind a unit-test or integration test where
practical. To smoke-test the whole chain:

```
# stream_key entropy
go test ./internal/live -run TestGenerateChannelName

# coupon race fix
go test ./internal/commerce -run TestCouponMaxUsesAtomic

# chat filter
go test ./internal/live -run TestFilterChatMessage

# token signer placeholder
go test ./internal/live -run TestTokenSigner
```

(Tests are scaffolded as part of Sprint 1; see `*_test.go` next to each
file.)
