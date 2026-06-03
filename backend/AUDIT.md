> **HISTORICAL DOCUMENT.** This file describes the **original Node.js
> backend** that was ported to Go across Phases 0-20. Kept for parity
> debugging and to recover the rationale behind quirks. Current
> production code lives in `cmd/`, `internal/`, `migrations/` — see
> `backend/README.md` and the top-level `CLAUDE.md`.
>
> Things mentioned here that are **NO LONGER** in the running stack:
> - Cloudinary → replaced by Cloudflare R2 in Phase 9
> - RabbitMQ → replaced by Redis Streams in Phase 11
> - Supabase REST/Auth SDK → Go uses pgx + custom JWT auth
> - Express middleware → Gin equivalents in `internal/httpx/`
> - LiveKit / Agora → SRS (RTMP/HLS/WHIP/SRT) in Phase 16

I now have enough information to produce the comprehensive audit. Let me compile it.

---

# Tropia Backend Audit â€” Node.js â†’ Go Port Reference

Audit of `c:\Users\Admin\Tropia\backend\src\`. Express monolith with Supabase (Postgres) as DB, Redis for cache/locks/rate-limit, RabbitMQ for events, multi-process worker model.

## 0. Entry Point & Middleware Stack

`src/index.js` mounts routes under `/api`. Global middleware order (applies to every route):

1. `helmet()` â€” CSP `default-src 'self'`, HSTS 1y, no X-Powered-By.
2. `cors({ origin: config.corsOrigin, credentials: true })` (origin defaults to `*`).
3. `app.set('trust proxy', 1)` â€” needed so `req.ip` honors `X-Forwarded-For` (used by rate-limiter and VNPay IP capture).
4. `requestId()` â€” sets `req.id` from `X-Request-ID` header or generates UUID; echoes back as `X-Request-ID`.
5. `cookieParser()`.
6. `express.json({ limit: '64kb' })`.
7. `sanitizeInput()` â€” recursively removes `__proto__`/`constructor`/`prototype` keys from `req.body` and `req.query`, strips null bytes (`\0`) and Unicode bidi overrides (U+202E, U+200F, U+200B) from strings.
8. `requestSizeGuard(64)` â€” **only for non-upload routes** (mounted with regex `/^(?!\/api\/upload)/`); 413 if `Content-Length > 64kb`.
9. `auditLog()` â€” wraps every response: logs to `error` for â‰¥500, `warn` for â‰¥400, `info` only for sensitive paths (`/api/auth/`, `/api/orders`, `/api/upload`). Anonymises last IPv4 octet (GDPR).
10. `passport.initialize()` (no session â€” JWT only).

Health check: `GET /health` â†’ `{ ok: true, service: 'tropia-backend', ts }`.

Routes mounted: `/api/auth`, `/api/live`, `/api/token`, `/api/orders`, `/api/upload`, `/api/categories`, `/api/shops`, `/api/products`, `/api/payment`, `/api/coupons`, `/api/cart`.

Final fallthrough: 404 `{ error: 'Route not found', code: 'NOT_FOUND' }`, then `errorHandler()`.

`errorHandler()` (`middleware/errorHandler.js`):
- Zod errors â†’ 422 `VALIDATION_ERROR` with `details: [{path, message}]`.
- `JsonWebTokenError` / `TokenExpiredError` â†’ 401 `UNAUTHORIZED`.
- `AppError` subclass â†’ respect `statusCode`/`code`/`details`.
- Anything else â†’ 500 `INTERNAL_ERROR`, full stack logged.

`AppError` subclasses (`errors/AppError.js`): `ValidationError(422)`, `AuthError(401)`, `ForbiddenError(403)`, `NotFoundError(404)`, `ConflictError(409)`, `RateLimitError(429)`, `PaymentError(402)`.

App startup calls `rabbitmq.connect()` (non-fatal â€” logs warning on failure).

---

## 1. Database Schema (inferred from Supabase queries)

All tables live in Supabase (Postgres). The backend uses the service-role key (bypasses RLS). UUID primary keys throughout, snake_case column names. There is at least one SQL view (`variant_detail`) and several Postgres RPC functions referenced via `supabase.rpc(...)`.

### 1.1 `profiles` â€” users (buyers/sellers/admins)
| column | type | notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `email` | text unique (lowercased) | |
| `password_hash` | text NULL | NULL for Google-only users |
| `name` | text | display name |
| `phone` | text NULL | |
| `shop_name` | text NULL | stored only at registration (separate from `shops.name`) |
| `role` | enum text | `buyer` \| `seller` \| `admin` (default `buyer`) |
| `avatar_url` | text NULL | |
| `google_id` | text NULL | |
| `status` | text | values used: `'deleted'` (soft delete) |
| `email_verified` | bool | gates login |
| `verify_token` | text NULL | sha256 hex (legacy â€” currently OTP via Redis is used) |
| `verify_token_expires` | timestamptz NULL | |
| `password_reset_token` | text NULL | sha256 hex |
| `password_reset_expires` | timestamptz NULL | |
| `failed_login_attempts` | int default 0 | |
| `locked_until` | timestamptz NULL | bumped 15min after 5 failed logins |
| `created_at` | timestamptz | implicit |
| `updated_at` | timestamptz | implicit |

### 1.2 `refresh_tokens`
| column | type | notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `user_id` | uuid FK â†’ profiles.id | |
| `token_hash` | text | sha256 of raw token |
| `family` | uuid | token-family for reuse detection â€” all tokens in family revoked on reuse |
| `expires_at` | timestamptz | 7-day TTL |
| `revoked` | bool default false | |
| `created_at` | timestamptz | |

### 1.3 `shops`
| column | type | notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `seller_id` | uuid FK â†’ profiles.id | one shop per seller (constraint `shops_seller_id_fkey` referenced) |
| `name` | text | |
| `slug` | text unique | |
| `description` | text NULL | |
| `logo_url` | text NULL | |
| `banner_url` | text NULL | |
| `rating` | numeric | |
| `total_sales` | int | |
| `follower_count` | int | |
| `is_active` | bool | |
| `created_at` / `updated_at` | timestamptz | |

### 1.4 `shop_follows`
| column | type | notes |
| --- | --- | --- |
| `user_id` | uuid FK | composite PK with shop_id |
| `shop_id` | uuid FK | |
| `followed_at` | timestamptz | |

### 1.5 `categories`
| column | type | notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `name` | text | |
| `slug` | text unique | |
| `parent_id` | uuid NULL FK â†’ categories.id | tree |
| `image_url` | text NULL | |
| `sort_order` | int | |
| `is_active` | bool | |

Note: `repositories/category.repository.js#countProductsByCategory` queries `products.category_id` but the actual schema uses junction table `product_categories` â€” this is dead/inconsistent code in the JS, important to flag for the Go port.

### 1.6 `products`
| column | type | notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `shop_id` | uuid FK â†’ shops.id | |
| `name`, `slug` (unique), `description` | text | |
| `images` | text[] | |
| `base_price` | int (VND) | |
| `sale_price` | int NULL (VND) | |
| `unit` | text default `'cÃ¡i'` | |
| `has_variants` | bool default false | |
| `rating` | numeric | |
| `review_count` | int | |
| `total_sold` | int | |
| `total_stock` | int | |
| `status` | text | `'draft' \| 'active' \| 'inactive' \| 'deleted'` (soft delete uses `'deleted'`) |
| `created_at` / `updated_at` | timestamptz | |

### 1.7 `product_categories` (M2M)
| column | type | notes |
| --- | --- | --- |
| `product_id` | uuid FK | |
| `category_id` | uuid FK | |
| `is_primary` | bool | exactly one row per product has `is_primary=true` |

Inner join used in browse (`product_categories!inner`).

### 1.8 `product_variants`
| column | type | notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `product_id` | uuid FK | |
| `sku` | text NULL | |
| `price` | int | |
| `sale_price` | int NULL | |
| `stock` | int default 0 | |
| `images` | text[] | |
| `is_active` | bool default true | |

### 1.9 `attribute_types` / `attribute_values` / `variant_attributes`
- `attribute_types(id, name, sort_order, ...)` â€” e.g. "Color", "Size".
- `attribute_values(id, attribute_type_id, value, display_name NULL, color_hex NULL, sort_order)`.
- `variant_attributes(variant_id, attribute_value_id)` â€” junction.

### 1.10 `variant_detail` (VIEW)
Read-only view that exposes variant + flattened attributes JSON. Selected as `variant_detail(*)`. Columns referenced: `id, sku, price, sale_price, stock, is_active, attributes`. `attributes` is presumably an aggregated JSON array of `{type, value, ...}`. Used by `cart.controller.addItem` and product detail.

### 1.11 `live_sessions`
| column | type | notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `seller_id` | uuid FK â†’ profiles.id | |
| `title`, `category` | text | |
| `agora_channel` | text | random `live_<16hex>` despite the LiveKit migration â€” name preserved for back-compat |
| `status` | text | `'live'` \| `'ended'` (default `'live'`) |
| `started_at` | timestamptz default now | |
| `ended_at` | timestamptz NULL | |
| `viewer_count` | int | maintained by trigger on `live_viewers` insert/delete |
| `like_count` | int | bumped by RPC `increment_likes(session_id)` |
| `order_count` | int | presumably incremented elsewhere (trigger or unseen path) |
| `revenue` | int | |
| `cart_add_count` | int | RPC `increment_cart_add(session_id)` |
| `follow_count` | int | RPC `increment_follow_count(session_id)` |

### 1.12 `live_session_products`
| column | type | notes |
| --- | --- | --- |
| `id` | uuid PK | doubles as a quasi-variant id â€” used in cart `variant_id` when added from live |
| `session_id` | uuid FK | |
| `product_name`, `image_url` | text | snapshot |
| `original_price`, `sale_price` | numeric | |
| `discount_pct` | numeric | |
| `stock_left` | int | decremented by `inventory.worker.js` |
| `sold_count` | int | |
| `unit` | text | |
| `category` | text NULL | |
| `sort_order` | int | |

### 1.13 `live_viewers`
PK `(session_id, user_id)`. Inserts/deletes drive `live_sessions.viewer_count` via DB trigger (per comment in `live.repository.js`).

### 1.14 `chat_messages`
| column | type | notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `session_id` | uuid FK | |
| `user_id` | uuid FK | |
| `username`, `avatar_url`, `message` | text | snapshot |
| `is_host` | bool NULL | inserted only when true (legacy schema accommodation) |
| `created_at` | timestamptz | |

### 1.15 `live_orders` â€” **all** order rows (live + non-live cart checkout)
| column | type | notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `session_id` | uuid NULL FK â†’ live_sessions.id | NULL for cart checkout |
| `product_id` | uuid NULL FK â†’ live_session_products.id | NULL for cart checkout |
| `product_name` | text NULL | populated for cart checkout (e.g. "X vÃ  2 sáº£n pháº©m khÃ¡c") |
| `buyer_id` | uuid FK â†’ profiles.id | |
| `buyer_name`, `buyer_avatar` | text NULL | snapshot |
| `quantity` | int | total quantity across items (for cart checkout) |
| `unit_price` | int | for cart checkout this stores the **subtotal** (pre-discount), see service code |
| `total_price` | int | final after discount |
| `discount_amount` | int default 0 | |
| `coupon_id` | uuid NULL FK â†’ coupons.id | |
| `status` | text | `'confirmed' \| 'cancelled' \| 'shipping' \| 'delivered'` |
| `payment_status` | text | `'pending' \| 'paid' \| 'failed'` |
| `payment_method` | text | `'cod' \| 'momo' \| 'zalopay' \| 'vnpay'` (case mixed when set by webhook: `'MoMo'`, `'ZaloPay'`, `'VNPay'`) |
| `transaction_id` | text NULL | |
| `paid_at` | timestamptz NULL | |
| `tracking_code` | text NULL | |
| `shipped_at` | timestamptz NULL | |
| `delivered_at` | timestamptz NULL | |
| `created_at` | timestamptz | |

**Watch out:** `unit_price` is semantically overloaded â€” it equals product unit price for `placeOrder`, but equals the cart **subtotal** in `cart.checkout.service.js`. The `notification.worker.js` and email template lean on this convention.

### 1.16 `coupons`
| column | type | notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `code` | text unique (uppercased) | |
| `discount_type` | text | `'percent'` \| `'fixed'` |
| `discount_value` | numeric | percent (0â€“100) or fixed VND |
| `min_order_value` | int default 0 | |
| `max_discount` | int NULL | cap when `percent` |
| `max_uses` | int NULL | NULL = unlimited |
| `used_count` | int default 0 | incremented by RPC `increment_coupon_uses(cid)` |
| `expires_at` | timestamptz | |
| `is_active` | bool default true | "delete" only soft-deactivates |
| `session_id` | uuid NULL FK â†’ live_sessions.id | NULL = platform-wide |
| `created_by` | uuid FK â†’ profiles.id | seller or admin |
| `created_at` | timestamptz | |

Upsert in `insertSessionCoupons` uses `onConflict: 'code'` (so codes are globally unique).

### 1.17 `coupon_usages`
| column | type | notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `coupon_id`, `user_id`, `order_id` | uuid FK | enforces one-use-per-user via lookup |

### 1.18 `cart_items`
| column | type | notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `user_id` | uuid FK | |
| `variant_id` | uuid | for live items this is actually a `live_session_products.id` |
| `product_id` | uuid | |
| `product_name`, `shop_id`, `shop_name`, `image_url` | text/uuid | snapshot |
| `attributes` | jsonb | from `variant_detail.attributes` (empty for live items) |
| `unit_price`, `original_price` | int | |
| `quantity` | int | |
| `is_selected` | bool default true | drives checkout selection |
| `added_at` | timestamptz | |

Uniqueness: `(user_id, variant_id)` is the upsert key in `repo.upsertItem` (does a `select â†’ update or insert` rather than relying on a unique constraint, so the constraint may or may not exist â€” defensive against duplicates).

### 1.19 Postgres RPC functions referenced
- `increment_likes(session_id uuid)` â€” bumps `live_sessions.like_count`.
- `increment_cart_add(session_id uuid)` â€” bumps `live_sessions.cart_add_count`.
- `increment_follow_count(session_id uuid)` â€” bumps `live_sessions.follow_count`.
- `increment_coupon_uses(cid uuid)` â€” bumps `coupons.used_count`.
- Triggers (implicit): `live_viewers` insert/delete maintains `live_sessions.viewer_count`.

---

## 2. HTTP Routes (complete)

Format: METHOD PATH â€” auth â€” role â€” description.

### 2.1 `/api/auth` â€” `routes/auth.js`
Rate limits: login `5/min` fail-closed, register `3/5min` fail-closed, reset/resend `3/5min` fail-open.

| Method | Path | Auth | Role | What it does |
| --- | --- | --- | --- | --- |
| POST | `/register` | none | â€” | Zod: email/pwd(â‰¥8, A-Z+digit)/fullName/phone?/shopName?/role(`buyer`\|`seller`,default `buyer`). Hashes pwd (bcrypt rounds=12), creates profile, auto-creates shop if seller (slugified from name + id prefix), generates 6-digit OTP into Redis key `email_otp:{userId}` TTL 10min, publishes `auth.email_otp`. Returns 201 with user. |
| POST | `/login` | none | â€” | Verifies email+pwd. Blocks if `status='deleted'`, `email_verified=false`, or `locked_until>now`. On wrong pwd: increments `failed_login_attempts`; at 5 sets `locked_until = now + 15min`. On success clears failure counters, issues tokens, sets `refresh_token` httpOnly cookie (path=`/api/auth`, sameSite=strict, secure in prod), returns `accessToken` + user. |
| POST | `/refresh` | none (needs cookie/body refreshToken) | â€” | sha256-hashes the raw refresh token, looks up in `refresh_tokens`. If revoked or expired, revokes whole `family` (reuse detection) and logs `refresh.token_reuse_detected`. Otherwise: revokes the used token (rotation), issues new access+refresh in same family. |
| POST | `/logout` | none (cookie) | â€” | Revokes one refresh token, clears cookie. |
| POST | `/logout-all` | yes | any | Revokes all tokens for `req.user.id`. |
| GET | `/me` | yes | any | Echoes back JWT claims. |
| POST | `/forgot-password` | none | â€” | Generates a 32-byte raw token, stores sha256 + `password_reset_expires = now+1h` on profile, publishes `auth.password_reset`. Always returns 200 (anti-enumeration). |
| POST | `/reset-password` | none | â€” | Body `{token, newPassword}`. sha256s the token, looks up profile, sets new bcrypt hash, clears reset fields and lock counters, revokes ALL refresh tokens for the user. |
| POST | `/verify-otp` | none | â€” | Body `{email, otp(6 digits)}`. Looks up Redis `email_otp:{userId}`, on match marks `email_verified=true` and publishes `user.registered` (triggers welcome email â€” note: the welcome email goes out **after** OTP verify, not after register). |
| POST | `/resend-verify-email` | none | â€” | Re-generates 6-digit OTP, re-publishes `auth.email_otp` (no-op if user not found / already verified). |
| GET | `/google` | none | â€” | Passport redirect to Google OAuth (`profile`, `email` scopes). |
| GET | `/google/callback` | passport | â€” | On success: issues tokens, generates One-Time-Code (24 random bytes hex) stored in Redis `oauth:otc:{code}` TTL 60s with `{accessToken, refreshToken}` JSON, then `res.redirect(GOOGLE_APP_DEEP_LINK?code=otc)` (default `tropia://auth/callback`). |
| GET | `/google/exchange?code=...` | none | â€” | Single-use exchange: looks up `oauth:otc:{code}`, deletes it, sets refresh cookie, returns accessToken. |

### 2.2 `/api/live` â€” `routes/live.js`
Limits: `apiLimit = 300/min` general, `chatLimit = 30/min` for posting chat.

| Method | Path | Auth | Role | Description |
| --- | --- | --- | --- | --- |
| GET | `/` | none | â€” | Active sessions list (cached `live:sessions:active` TTL 20s). Joins profile + `live_session_products`, enriches each session with `shop_id` by separately fetching `shops` by `seller_id`. |
| GET | `/:id` | none | â€” | Single session (cached `live:session:{id}` TTL 10s). |
| POST | `/start` | yes | seller, admin | Body schema (see `live.controller.startSchema`): title/category/products[â‰¤20]/coupons[â‰¤5]. Creates `live_sessions` row with a generated `agora_channel` (16-hex), inserts `live_session_products` rows, upserts `coupons` (onConflict by `code`). Invalidates `live:sessions:*` cache. Returns `{session, agoraChannel}`. |
| POST | `/:id/end` | yes | owner or admin | Sets status=`ended`, `ended_at=now`. |
| POST | `/:id/join` | yes | any | Upsert `live_viewers` (idempotent). 204. |
| POST | `/:id/leave` | yes | any | Delete `live_viewers`. 204. |
| POST | `/:id/like` | **none** | â€” | Bumps `like_count` via RPC. (No auth â€” anyone with session id can spam, see notes.) |
| GET | `/:id/chat?limit=` | none | â€” | Returns up to `min(limit||50, 100)` recent chats, oldest-first. |
| POST | `/:id/chat` | yes | any | `chatLimit`. Body `{messageâ‰¤500, type:text\|emoji, isHost?}`. Inserts into `chat_messages` with username from JWT (`fullName`/`name` fallback "Viewer"); username overridden to "Trá»£ lÃ½ AI" when `isHost=true`. |
| GET | `/:id/stats` | none | â€” | Reads `viewer_count,like_count,order_count,revenue,status,cart_add_count,follow_count`. |
| POST | `/:id/ai-suggestions` | yes | any | Calls DeepSeek to generate 3 short Vietnamese viewer questions. **Enriches** prompt with product names from the live session DB-side (overrides client values if any product exists). |
| POST | `/:id/ai-reply` | yes | any | Body `{question}`. DeepSeek auto-reply (<20 words). Enriches productName/category from DB (mandatory if no client-provided fallback). |
| GET | `/:id/coupons` | yes | any | Active coupons attached to this session (no expiry filter â€” validated at checkout). |
| POST | `/:id/broadcast-coupon` | yes | seller, admin | `chatLimit`. Posts a system chat message `ðŸŽ« Coupon: CODE â€“ Ãp dá»¥ng khi Ä‘áº·t hÃ ng!` as user "Trá»£ lÃ½ Live". |
| POST | `/:id/track-cart-add` | yes | any | RPC increments `cart_add_count`. 204. |
| POST | `/:id/track-follow` | yes | any | RPC increments `follow_count`. 204. |
| POST | `/:id/analyze` | yes | seller, admin | Fetches session + stats, calls DeepSeek `analyzeLiveSentiment` â†’ `{sentiment, summary, tips[4]}`. |

### 2.3 `/api/token` â€” `routes/token.js`
| Method | Path | Auth | Role | Description |
| --- | --- | --- | --- | --- |
| POST | `/livekit` | yes | any (RBAC enforced inline) | Body: `{sessionId?, channelName?, uid=0, role=publisher\|subscriber}`. If role=publisher and JWT role âˆ‰ {seller,admin} â†’ **silently downgraded** to subscriber (no error). If only `sessionId` given, resolves to `live_sessions.agora_channel`. Mints LiveKit JWT (TTL 3600s) with identity `${user.id}_${uid}` and grants `{roomJoin, room, canPublish:true|false, canSubscribe:true}`. Returns `{token, wsUrl, room, identity, expiresIn}`. |

### 2.4 `/api/orders` â€” `routes/orders.js`
`orderLimit = 10/min` per user, fail-closed.

| Method | Path | Auth | Role | Description |
| --- | --- | --- | --- | --- |
| POST | `/` | yes | any | `placeOrder` (live-session single-product). See Â§6.1. |
| POST | `/checkout` | yes | any | `checkoutCart` (cart-based, multi-item, single order row). See Â§6.2. |
| GET | `/my/list?page&limit` | yes | any | Paginated user orders, joins to `live_session_products` + `live_sessions(title)`. |
| GET | `/:sessionId` | yes | session owner or admin | Lists orders for a session (BOLA-protected â€” returns 404 with `bola.orders_access_denied` event for non-owners). |

### 2.5 `/api/upload` â€” `routes/upload.js`
All multer in-memory, 5MB/file, max 10 files per request. JPG/JPEG/PNG/WEBP only.

| Method | Path | Auth | Role | Description |
| --- | --- | --- | --- | --- |
| POST | `/avatar` | yes | any | field `image`. Cloudinary `tropia/avatars/avatar_{userId}`, 400Ã—400 face-fill, overwrite. |
| POST | `/product` | yes | seller, admin | field `images[]`, body `productId`. `tropia/products/product_{productId}_{idx}`, 800Ã—800 limit. |
| POST | `/variant` | yes | seller, admin | field `images[]` (â‰¤5), body `variantId`. `tropia/products/variants/variant_{variantId}_{idx}`. |
| POST | `/shop` | yes | seller, admin | field `image`, body `shopId`. 1200Ã—400 fill. |
| POST | `/temp` | yes | seller, admin | field `image`. `tropia/products/temp_{userId}_{ts}`, no-overwrite. |
| POST | `/live` | yes | seller, admin | field `image`, body `sessionId`. 1280Ã—720 fill. |

### 2.6 `/api/categories` â€” `routes/categories.js`
| Method | Path | Auth | Role | Description |
| --- | --- | --- | --- | --- |
| GET | `/` | none | â€” | Cached `categories:all` TTL 300s. |
| GET | `/:slug` | none | â€” | Includes `products(count)` aggregate. |
| POST | `/` | yes | admin | Create. |
| PATCH | `/:id` | yes | admin | Update. |
| DELETE | `/:id` | yes | admin | Hard delete â€” rejects with 409 if any active product still uses this category (note: counter query uses `products.category_id` which is inconsistent with M2M `product_categories` table; will likely always return 0 in current schema). |

### 2.7 `/api/shops` â€” `routes/shops.js`
| Method | Path | Auth | Role | Description |
| --- | --- | --- | --- | --- |
| GET | `/` | none | â€” | Active shops, sorted by `total_sales`. |
| GET | `/me/info` | yes | seller, admin | Current user's shop or null. |
| GET | `/me/following` | yes | any | Followed shops, paginated. |
| GET | `/:slug` | optional | â€” | `slug` may also be `shops.id` or `seller_id` (UUID). Adds `is_following` for logged-in caller. |
| POST | `/` | yes | seller, admin | One per seller. Conflicts on slug or existing shop. |
| PATCH | `/:id` | yes | owner or admin | Slug uniqueness re-checked. |
| GET | `/:id/follow-status` | yes | any | `{followed: bool}`. |
| POST | `/:id/follow` | yes | any | Upsert `shop_follows`. `:id` may be seller_id; resolved via `findShopBySlug`. |
| DELETE | `/:id/follow` | yes | any | Delete `shop_follows`. |

### 2.8 `/api/products` â€” `routes/products.js`
| Method | Path | Auth | Role | Description |
| --- | --- | --- | --- | --- |
| GET | `/attributes` | none | â€” | All attribute_types + values. |
| POST | `/attributes/values` | yes | admin | Insert attribute_value. |
| GET | `/` | none | â€” | Browse with filters: `category, shop, search (Postgres FTS plain/simple), sort (price_asc\|price_desc\|newest\|rating\|default total_sold), min_price, max_price, page, limit`. Returns `{data, pagination}`. |
| GET | `/seller/list` | yes | seller, admin | Caller's products, filterable by `status`. |
| GET | `/shop/:shopId` | none | â€” | Paginated active products of shop. |
| GET | `/:slug` | none | â€” | Single product (cached `product:{slug}` TTL 30s). 404 with non-existent slug â€” throws inside cache loader (so loader throws on miss). |
| POST | `/quick-create` | yes | seller, admin | "Quick" for live: just `{name, description?, price, stock, imageUrl?}`. Backend auto-slugs name+timestamp, sets `status='active'`, creates default variant with no attributes. |
| POST | `/` | yes | seller, admin | Full create with M2M categories and variants. `status='draft'`. |
| PATCH | `/:id` | yes | owner or admin | Partial update; cannot include `variants`. |
| PATCH | `/:id/status` | yes | owner or admin | `{status: draft\|active\|inactive}`. |
| DELETE | `/:id` | yes | owner or admin | Soft delete (`status='deleted'`). |
| POST | `/:id/variants` | yes | owner or admin | Add one variant + its `variant_attributes`. |
| PATCH | `/:id/variants/:variantId` | yes | owner or admin | Update variant. |
| DELETE | `/:id/variants/:variantId` | yes | owner or admin | Hard delete variant. |

Ownership check (`assertOwner`): joins `products â†’ shops!inner(seller_id)` and compares to `req.user.id`.

### 2.9 `/api/payment` â€” `routes/payment.js`
`paymentLimit = 10/min` fail-closed.

| Method | Path | Auth | Role | Description |
| --- | --- | --- | --- | --- |
| POST | `/momo` | yes | any | Init MoMo. Body `{orderId}`. See Â§6.3. |
| GET | `/momo/callback` | none | â€” | Browser callback; verifies code, marks paid, redirects to `${CLIENT_URL}/payment/{success\|failed}?orderId=`. |
| GET | `/momo/result` | none | â€” | Same logic but redirects to Flutter deep route `${CLIENT_URL}/#/payment-result?status=&orderId=&method=momo`. |
| POST | `/momo/ipn` | none | â€” | Verified webhook (`MOMO_IPN_URL`). Always 200 `{message: ok}` on success, 400 on failure. |
| POST | `/momo/check` | yes | any | Calls MoMo `/query` endpoint. |
| POST | `/zalopay` | yes | any | Init ZaloPay. |
| POST | `/zalopay/callback` | none | â€” | Server webhook. Responds `{return_code:1, return_message:'success'}` or 0/'fail'. |
| POST | `/zalopay/check` | yes | any | Query ZaloPay status. |
| POST | `/vnpay` | yes | any | Init VNPay redirect URL. Captures `X-Forwarded-For` (first IP). |
| GET | `/vnpay/return` | none | â€” | Verifies HMAC-SHA512 signature, marks paid, redirects. |
| GET | `/vnpay/result` | none | â€” | Same but Flutter deep route. |

### 2.10 `/api/coupons` â€” `routes/coupons.js`
| Method | Path | Auth | Role | Description |
| --- | --- | --- | --- | --- |
| POST | `/validate` | yes | any | `20/min`. Body `{code, orderTotal}`. Returns discount details â€” applies the same logic as checkout (per-user uniqueness, min_order, max_uses, max_discount cap). |
| GET | `/available` | yes | any | Platform-level coupons (`session_id IS NULL`, active, not expired). |
| GET | `/shop/:shopId` | yes | any | Coupons linked to that shop's live sessions. `:shopId` may be `shops.id` or `seller_id` â€” code does parallel lookup + fallback. |
| GET | `/` | yes | admin | List all (paginated, `?all=true` to include expired). |
| POST | `/` | yes | admin | Create. |
| PATCH | `/:id` | yes | admin | Update. |
| DELETE | `/:id` | yes | admin | Soft (deactivate `is_active=false`). |

Note: `controllers/coupon.controller.js` defines `getMyCoupons` but it is **not wired** to any route in `routes/coupons.js` (dead code; possibly intended `/mine`).

### 2.11 `/api/cart` â€” `routes/cart.js`
Entire router gated by `authenticate`.

| Method | Path | Description |
| --- | --- | --- |
| GET | `/` | Returns `{items, summary:{totalItems, totalPrice, totalSaving}}` over **selected** items only. |
| POST | `/items` | Body `{variantId, quantity}`. Looks up `product_variants` (or first active variant of product if `variantId` is actually a product id), fetches `variant_detail.attributes`, snapshots product+shop, upserts cart_item (qty additive). |
| POST | `/items/from-live` | Body `{liveProductId, sessionId, quantity}`. Uses `live_session_products` snapshot. `variant_id` stored as the live product id; attributes empty. |
| PATCH | `/items/:id/qty` | Body `{quantity}` (1â€“999). |
| PATCH | `/items/:id/select` | Body `{is_selected: bool}`. |
| PATCH | `/select-all` | Body `{is_selected: bool}`. |
| DELETE | `/items/:id` | Single delete. |
| DELETE | `/items/selected` | Bulk delete by `is_selected=true`. |

Note: route registration order â€” `/items/:id/...` patterns are registered before `/items/selected`, which means **`DELETE /items/selected` is actually routed by Express as `/items/:id` with `id='selected'`**, returning 200 because `repo.removeItem` happily matches zero rows. This is a real bug to flag, not just a port concern.

---

## 3. External Integrations

All `process.env` lookups happen in `src/config/*` or directly inline.

### 3.1 Supabase (DB) â€” `lib/supabase.js`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_KEY` (service-role key, bypasses RLS).
- `auth: { persistSession: false }` â€” server side only.

### 3.2 Cloudinary â€” `lib/cloudinary.js`
- `CLOUDINARY_CLOUD_NAME`
- `CLOUDINARY_API_KEY`
- `CLOUDINARY_API_SECRET`
- Used in `routes/upload.js` only. `uploadBuffer` uses `upload_stream` so Go port needs the equivalent signed unsigned upload via REST.

### 3.3 LiveKit â€” `routes/token.js` via `livekit-server-sdk`
- `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_HOST` (wss://...).
- Server returns 500 if any are missing.
- `AccessToken({identity, ttl=3600}).addGrant({roomJoin, room, canPublish, canSubscribe})` â†’ JWT.
- Note: import includes `RoomServiceClient` but it's not used (placeholder for future room/admin ops).

### 3.4 MoMo â€” `services/payment.service.js`, `config/payment.js`
- `MOMO_ACCESS_KEY` (default `F8BBA842ECF85`)
- `MOMO_SECRET_KEY` (default sandbox key in code)
- `MOMO_PARTNER_CODE` (default `MOMO`)
- `MOMO_REDIRECT_URL` â€” where MoMo sends user after pay
- `MOMO_IPN_URL` â€” webhook
- `MOMO_API_URL` â€” sandbox by default
- Signature: HMAC-SHA256 over a `key=value&...` string (specific key ordering for create vs IPN).
- IPN raw signing string includes 13 fields; create signing string includes 10.
- `requestType: 'payWithMethod'`, `autoCapture: true`.
- `extraData` is `base64({orderId})` â€” used to look up original UUID order id on the return.

### 3.5 ZaloPay â€” same module
- `ZALOPAY_APP_ID`, `ZALOPAY_KEY1`, `ZALOPAY_KEY2`
- `ZALOPAY_CALLBACK_URL`, `ZALOPAY_REDIRECT_URL`
- `ZALOPAY_API_CREATE` (sandbox default), `ZALOPAY_API_QUERY`
- Create MAC: HMAC-SHA256(key1) over `appId|appTransId|appUser|amount|appTime|embedData|item`.
- `appTransId` format: `YYMMDD<8hex>` â€” current code uses `YYYYMMDD<8hex>` which is wrong per ZaloPay spec (they require `yyMMdd`, not 8-char date). Flag for port: replicate exactly OR fix.
- Callback MAC: HMAC-SHA256(**key2**) over raw `data` string; embed_data inside contains the canonical orderId.

### 3.6 VNPay â€” same module
- `VNP_TMN_CODE`, `VNP_HASH_SECRET`, `VNP_URL`, `VNP_RETURN_URL`.
- Signing: sort params alphabetically, build `k=v&k=v` (no URL-encoding when signing â€” buffer used directly), HMAC-SHA512 with hex digest. `vnp_SecureHash` excluded from the signed set on return.
- Amount in VND Ã— 100. `vnp_CreateDate` is `yyyyMMddHHmmss` in Asia/Ho_Chi_Minh.
- Order id reverse-extracted from `vnp_OrderInfo` by stripping `'Thanh toan don hang '` prefix â€” **fragile**.

### 3.7 RabbitMQ â€” `lib/rabbitmq.js`
- `RABBITMQ_URL` (default `amqp://guest:guest@localhost:5672`).
- Single topic exchange `tropia.events` (durable).
- Auto-reconnect every 5s on close/error.
- Publishers use `persistent: true`.
- Subscribers: `prefetch(1)`, ack on success, **nack-without-requeue on error** (drops poison messages â€” they are not DLQ'd; flag for port to add a DLX).

Events catalog (routing keys):
- Producer side (`publish`):
  - `auth.email_otp` â€” from `register`/`resendVerifyEmail`. Payload: `{userId, email, name, otp}`.
  - `user.registered` â€” from `verifyEmailOtp` (after OTP success). Payload: `{email, name}`.
  - `auth.password_reset` â€” from `forgotPassword`. Payload: `{userId, resetToken}` (raw token, NOT the hash).
  - `order.created` â€” from `placeOrder` & `checkoutCart`. Payload: `{orderId, buyerName, productName, quantity, totalPrice, discountAmount, sessionTitle}` (live) or with no `buyerId`/`productId` (cart). Note: `placeOrder` omits `buyerId` and `productId` so the inventory worker can't decrease stock for live placeOrder â€” see Â§6.1.
  - `payment.success` â€” from `markPaidAndNotify`. Payload: `{orderId, buyerId, method, transId, amount}`.
  - `order.cancelled` â€” from `order-status.worker` on payment.failed. Payload: `{orderId, buyerId, productId, quantity, reason}`.
- Other consumer-bound events (no producer found in repo, expected to be published by ops tooling):
  - `payment.failed` â€” consumed by order-status.
  - `order.shipped`, `order.delivered` â€” consumed by order-status.

Queue/binding map (one queue per consumer):

| Queue name | Pattern | Worker |
| --- | --- | --- |
| `inventory.order.created` | `order.created` | inventory.worker |
| `inventory.order.cancelled` | `order.cancelled` | inventory.worker |
| `order-status.payment.success` | `payment.success` | order-status.worker |
| `order-status.payment.failed` | `payment.failed` | order-status.worker |
| `order-status.order.shipped` | `order.shipped` | order-status.worker |
| `order-status.order.delivered` | `order.delivered` | order-status.worker |
| `notif.user.registered` | `user.registered` | notification.worker |
| `notif.order.created` | `order.created` | notification.worker |
| `notif.payment.success` | `payment.success` | notification.worker |
| `notif.auth.email_otp` | `auth.email_otp` | notification.worker |
| `notif.auth.password_reset` | `auth.password_reset` | notification.worker |
| `notif.order.cancelled` | `order.cancelled` | notification.worker |

### 3.8 Email / SMTP â€” `lib/email.js` (nodemailer)
- `EMAIL_HOST` (default `smtp.gmail.com`), `EMAIL_PORT` (587), `EMAIL_SECURE` (false), `EMAIL_USERNAME`, `EMAIL_PASSWORD`, `EMAIL_FROM_NAME` (default `Tropia`).
- Templates: `tplWelcome`, `tplOrderConfirm`, `tplPasswordReset`, `tplEmailOtp`, `tplPaymentSuccess` (the rich payment template with items table).
- Triggers (in `notification.worker.js`):
  - `user.registered` â†’ welcome email (after OTP, not after register).
  - `order.created` â†’ order confirmation.
  - `payment.success` â†’ payment success email with full items table (fetches order from `live_orders`).
  - `auth.email_otp` â†’ OTP code (6 digits).
  - `auth.password_reset` â†’ reset link `${CLIENT_URL}/reset-password?token=${rawToken}`.
  - `order.cancelled` â†’ cancellation email.

### 3.9 DeepSeek AI â€” `services/deepseek.service.js`
- `DEEPSEEK_API_KEY` env (with **hardcoded sandbox-style key fallback** â€” flag for port: do not port that fallback).
- Host: `api.deepseek.com`, path `/chat/completions`, model `deepseek-chat`, timeout 15s.
- Three calls:
  - `getAiSuggestions(productName, category, recentComments[])` â€” used by `POST /api/live/:id/ai-suggestions`. Returns `string[3]` Vietnamese viewer questions.
  - `getAutoReply(question, productName, category)` â€” used by `POST /api/live/:id/ai-reply`. Returns short Vietnamese answer.
  - `analyzeLiveSentiment(stats, title)` â€” used by `POST /api/live/:id/analyze`. Returns `{sentiment âˆˆ {tÃ­ch cá»±c|trung bÃ¬nh|cáº§n cáº£i thiá»‡n}, summary, tips[4]}`.
- JSON extraction uses a regex match (`/\{[\s\S]*"sentiment"[\s\S]*\}/`) on the model response â€” brittle.

### 3.10 Google OAuth â€” `lib/passport.js`
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_CALLBACK_URL` (default `http://localhost:3000/api/auth/google/callback`), `GOOGLE_APP_DEEP_LINK` (default `tropia://auth/callback`).
- Strategy: on profile, look up by email; if exists, refresh google_id + avatar if missing. If `status='deleted'` returns error. If not found, insert new profile with `role='buyer'`, NULL `password_hash`, returns it.
- Login flow ends in `googleCallback` â†’ OTC stored in Redis 60s â†’ deep-link redirect â†’ app calls `GET /api/auth/google/exchange?code=`.

### 3.11 Redis â€” `lib/redis.js`
- `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`.
- Used for:
  - **Cache-aside** (`cacheAside(key, loader, ttl)`) â€” categories(300s), live sessions list(20s), single session(10s), product by slug(30s). Fail-open (fallback to loader on Redis error).
  - **Distributed lock** via Lua (`acquireLock(resource, {ttlMs, retries, retryDelayMs})`) â€” used in `placeOrder` for `product:{productId}:stock`.
  - **Sliding-window rate-limit** via Lua + ZSET `rl:{path}:{userId|ip}`. `failClosed=true` for auth/orders/payment.
  - **OTP store** `email_otp:{userId}` TTL 600s.
  - **OAuth OTC** `oauth:otc:{code}` TTL 60s.
  - **Cache invalidation** `invalidatePattern(pattern)` via SCAN+DEL (used after live start/end, product/category/shop updates).

### 3.12 JWT â€” `middleware/auth.js`
- `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET` (both required at boot; will `throw` on missing).
- `JWT_ACCESS_EXPIRES_IN` (default `15m`), `JWT_REFRESH_EXPIRES_IN` (default `7d`).
- Access token: `issuer='tropia'`, `audience='tropia-client'`. Payload: `{id, role, email, fullName}` (note: `fullName` not `name`).
- Refresh token: opaque random hex (NOT a JWT despite the file using `jsonwebtoken` for verifyRefreshToken â€” actually the implementation in `auth.service.issueTokens` uses `repo.makeTokenPair()` which generates 48 random bytes; `signRefreshToken` is exported but never called). Stored as sha256 hash in `refresh_tokens` table with `family` UUID.

---

## 4. Background Workers

Three separate Node processes. Each calls `rabbitmq.connect()` then `subscribe(routingKey, queueName, handler)`. PM2 names suggested in comments.

### 4.1 `inventory.worker.js`
Consumes:
- `order.created` (`inventory.order.created`) â†’ if payload has `productId` and `quantity`, fetch `live_session_products`, set `stock_left = max(0, stock_left - qty)`, `sold_count += qty`. **Note: `placeOrder` doesn't include `productId` in the payload, only `orderId` â€” this means the live-flow stock decrement is currently broken; only the legacy/expected path with `productId` works.** This is a real bug worth flagging.
- `order.cancelled` (`inventory.order.cancelled`) â†’ reverse: `stock_left += qty`, `sold_count = max(0, sold_count - qty)`.

### 4.2 `order-status.worker.js`
Consumes:
- `payment.success` â†’ updates `live_orders` set `status='confirmed', payment_status='paid', payment_method, transaction_id, paid_at=now`. Idempotent on `payment_status='paid'`. **Duplicate logic** with `markPaidAndNotify` (already does the same DB update inline) â€” both run for each success event.
- `payment.failed` â†’ cancels order, publishes `order.cancelled` with `{orderId, buyerId, productId, quantity, reason}` for inventory restock.
- `order.shipped` â†’ status='shipping', `tracking_code`, `shipped_at`. Only if currently `confirmed`.
- `order.delivered` â†’ status='delivered', `delivered_at`. Only if currently `shipping`.

### 4.3 `notification.worker.js`
Consumes (sends email per Â§3.8 list).

---

## 5. Auth Flow

### 5.1 Registration
1. `POST /api/auth/register` (rate-limited 3/5min fail-closed).
2. Validate (Zod): email/pwd(min 8 with uppercase+digit)/fullName/phone?/shopName?/role.
3. `repo.emailExists` â€” 409 `ConflictError` if exists.
4. bcrypt-hash pwd (12 rounds).
5. Insert `profiles` row.
6. If `role='seller'`, normalize-then-slugify `shopName||"<fullName>'s Shop"`, insert `shops` row with `is_active=true`, slug = `${prefix}-${userIdFirst8}`.
7. Generate 6-digit OTP; store `email_otp:{userId}` in Redis with 10-min TTL.
8. Publish `auth.email_otp` (welcome NOT sent yet).
9. Return 201 `{user}`.

User cannot log in yet â€” `email_verified=false`.

### 5.2 Email verify
- `POST /api/auth/verify-otp {email, otp}` â€” strict 6-digit regex. Reads `email_otp:{userId}` from Redis. On match: clears key, sets `email_verified=true`, publishes `user.registered` (which triggers welcome email).
- Idempotent: already-verified users return success without re-checking OTP.
- `POST /api/auth/resend-verify-email {email}` â€” re-generates OTP, re-publishes, anti-enumeration (always returns same message).

### 5.3 Login (local)
1. `POST /api/auth/login` (5/min fail-closed).
2. Look up by email.
3. Reject if `!user || status='deleted'` (404-class, same error message anti-enumeration).
4. Reject if `!email_verified`.
5. Reject if `locked_until > now`.
6. `bcrypt.compare(password, password_hash)`:
   - Wrong pwd â†’ increment `failed_login_attempts`. At â‰¥5, set `locked_until = now+15min`, log `login.brute_force_lockout`.
   - Right pwd â†’ clear counters.
7. `issueTokens(user)`:
   - `makeTokenPair()` â†’ raw refresh = 48 random bytes hex, hash = sha256(raw), `expires_at = now+7d`, `family = uuidv4()`.
   - Insert into `refresh_tokens`.
   - Sign access JWT with claims `{id, role, email, fullName: user.name}`.
8. Set `refresh_token` cookie (httpOnly, sameSite=strict, secure in prod, path=`/api/auth`, maxAge=7d).
9. Return `{accessToken, user:{id,email,name,role,avatarUrl}}`.

### 5.4 Login (Google OAuth)
1. App opens browser to `GET /api/auth/google` (passport redirect).
2. Google â†’ `GET /api/auth/google/callback`.
3. Passport strategy (`lib/passport.js`) creates/updates profile.
4. Controller `googleCallback`:
   - `issueTokens(user)` â€” same as local login.
   - `storeOtc(access, refresh)` â†’ Redis `oauth:otc:{hex24}` TTL 60s.
   - `res.redirect("${GOOGLE_APP_DEEP_LINK}?code=${otc}")` â€” default `tropia://auth/callback?code=...`.
5. Flutter intercepts deep link â†’ calls `GET /api/auth/google/exchange?code=...`.
6. Server pops from Redis (single-use), sets refresh cookie, returns `{accessToken}`.

### 5.5 Refresh (rotation + reuse detection)
1. `POST /api/auth/refresh` â€” reads `refresh_token` from cookie (or body).
2. `tokenHash = sha256(raw)`; look up in `refresh_tokens`.
3. If `!stored || revoked || expired`: **if stored exists**, revoke entire `family` (treat as reuse attack), log `refresh.token_reuse_detected`. Throw 401.
4. Otherwise: revoke the used token (single row by `token_hash`), issue new pair **reusing same `family` UUID**, return new access + set new refresh cookie. Logs `refresh.rotated`.

### 5.6 Logout
- `POST /api/auth/logout` â€” revoke single token, clear cookie. 204.
- `POST /api/auth/logout-all` (auth required) â€” revoke all tokens for user, clear cookie. 204.

### 5.7 Password reset
- `POST /api/auth/forgot-password` â€” generates 32-byte raw token, stores sha256 + `expires=now+1h`, publishes `auth.password_reset {userId, resetToken}` (raw token in event â€” relay via secure email). Always 200.
- `POST /api/auth/reset-password {token, newPassword}` â€” sha256 token, look up profile, verify not expired, set new bcrypt hash, clear reset fields and lock counters, revoke all refresh tokens.

### 5.8 RBAC (`authorize(...roles)`)
After `authenticate`, ensures `req.user.role âˆˆ roles`. Roles seen in code: `buyer`, `seller`, `admin`. Routes using `authorize`:
- `seller, admin`: most product CRUD, shop CRUD, live `/start`, live `/broadcast-coupon`, live `/analyze`, upload (`product, variant, shop, temp, live`).
- `admin` only: categories CRUD, coupon CRUD/list, `POST /products/attributes/values`.
- Token route does its own RBAC inline (downgrade to subscriber if requesting publisher without role).

### 5.9 BOLA defenses
- `payment.service.getOrderForPayment`: throws `NotFoundError` (not Forbidden) if `order.buyer_id !== userId`, logs `payment.bola` event.
- `order.service.getSessionOrders`: throws `NotFoundError` for non-owner non-admin, logs `bola.orders_access_denied`.
- `cart.repository`: all mutations append `.eq('user_id', userId)` so seller's IDOR is structurally impossible.

---

## 6. Notable Business Logic

### 6.1 Place order (live, single product) â€” `services/order.service.placeOrder`
1. Acquire Redis lock `lock:product:{productId}:stock` (ttl=5s, retries=5, 200/400/600ms backoff).
2. Fetch `live_session_products` row (sale_price, stock_left, session_id, joined session title).
3. Reject 409 if `stock_left < quantity`.
4. If `couponCode`: call `couponSvc.applyCoupon(code, buyerId, totalPrice)` (validates expiry, max_uses, min_order_value, per-user uniqueness via `coupon_usages`, computes discount with `max_discount` cap).
5. Insert `live_orders` row with status `confirmed` + payment_status `pending`, payment_method `cod`. (Even when paid via gateway later â€” gets updated by `markPaidAndNotify` / order-status worker.)
6. If coupon applied: insert `coupon_usages` row + RPC `increment_coupon_uses(cid)`.
7. Publish `order.created` â€” payload has NO `productId`, NO `buyerId` â€” this breaks the inventory worker for the live flow.
8. Release lock.

Returns `{order, product, discountAmount}`.

### 6.2 Cart checkout â€” `services/cart.checkout.service.checkoutCart`
1. Compute `subtotal = Î£(unitPrice Ã— quantity)` from client-trusted items.
2. If `couponCode`: try `applyCoupon`, on failure swallow and log warning.
3. Else if `clientDiscount > 0`: trust client up to `min(clientDiscount, subtotal)` (this is a hole â€” front-end shop coupons are accepted at face value).
4. `grandTotal = max(0, subtotal - totalCouponDiscount)`.
5. Concatenate display name: `"<firstProductName> vÃ  N sáº£n pháº©m khÃ¡c"`.
6. Insert single `live_orders` row:
   - `session_id=null`, `product_id=null` (cart, not live).
   - `quantity = Î£ quantity`.
   - **`unit_price = subtotal`** (overloaded; the email template treats it as subtotal).
   - `total_price = grandTotal`.
   - `status='confirmed', payment_status='pending', payment_method='cod'`.
   - `product_name = "..."`, `coupon_id`.
7. `coupon_usages` row if coupon applied (swallows errors).
8. Publish `order.created` with payload `{orderId, buyerName, productName, quantity, totalPrice, discountAmount, sessionTitle:'Tropia Store'}` (no `productId`).
9. Returns `{orders: [orderOut], summary: {subtotal, couponDiscount, grandTotal, paymentMethod}}`.

The `paymentMethod` field in body is just stored in response â€” never persisted into `live_orders.payment_method` (which stays `'cod'` until the payment webhook overrides it).

### 6.3 Payment init (MoMo example)
1. `getOrderForPayment(orderId, userId)` â€” BOLA check, rejects if already paid.
2. Generate `requestId = "${partnerCode}${ts}"`, `amount = round(total_price)`, `extraData = base64({orderId})`.
3. Build raw signing string (10 fields, fixed order), HMAC-SHA256 with secretKey.
4. POST to `${MOMO_API_URL}/v2/gateway/api/create` with all fields + `signature`.
5. If `resultCode === 0`, log `payment.momo.initiated`, return `{payUrl, deeplink}`.

### 6.4 Payment confirmation
Two paths can both confirm:
1. **Browser redirect** (`GET /momo/callback` or `/momo/result`): parses query, base64-decodes `extraData` to get our `orderId`, calls `markPaidAndNotify`.
2. **IPN webhook** (`POST /momo/ipn`): verifies signature against 13-field raw string, calls `markPaidAndNotify`.

`markPaidAndNotify`:
- Updates `live_orders` set `status='confirmed', payment_status='paid', payment_method, transaction_id, paid_at`.
- Publishes `payment.success {orderId, buyerId, method, transId, amount}`.

Then `order-status.worker` consumes `payment.success` and **re-runs the same update** (idempotent). Duplicate work but harmless.

`notification.worker` consumes `payment.success`, fetches full order, sends rich payment-success email with itemized table.

### 6.5 Live stream start
1. `POST /api/live/start` (seller/admin) â€” Zod-validated body.
2. Generate `agora_channel = "live_<16hex>"` (legacy name â€” actually used by LiveKit; field is historical).
3. Insert `live_sessions` with `status='live'`, `started_at=now` (default).
4. If products: bulk-insert `live_session_products` (with `sort_order` from input array index).
5. If coupons: **upsert by `code`** into `coupons` with `session_id=session.id, created_by=sellerId`. The upsert means existing platform coupons with the same code get reassigned to this session â€” potential foot-gun.
6. Invalidate `live:sessions:*` cache.
7. Return `{session, agoraChannel}`.

Client then calls `POST /api/token/livekit {sessionId, role:'publisher'}` to mint a LiveKit JWT.

### 6.6 Live stream end
- `POST /api/live/:id/end`: owner or admin only. Sets `status='ended', ended_at=now`. Invalidates `live:session:{id}*` and `live:sessions:*` caches.
- Does NOT close LiveKit rooms server-side.

### 6.7 Cart "addItemFromLive"
The cart system has two flavors of items stored in the same `cart_items` table:
- Normal: `variant_id` is `product_variants.id`, attributes JSON populated.
- Live: `variant_id` is `live_session_products.id`, attributes empty.

This means `variant_id` is NOT a real FK to `product_variants` (mixed identifiers). The Go port should either separate them or make this explicit.

---

## 7. Notable / Tricky Things (Things hard to port without seeing)

1. **`unit_price` semantic overload in `live_orders`**: in `placeOrder` it's the per-item unit price; in `checkoutCart` it's the subtotal across all items. The payment-success email template depends on this.

2. **`variant_id` overload in `cart_items`**: holds either `product_variants.id` OR `live_session_products.id`. The "upsert" (`select then update or insert`) uses no DB-level uniqueness, so collisions between a real variant UUID and a live-product UUID are theoretically possible but UUID collisions are negligible.

3. **Cart route ordering bug**: `DELETE /items/selected` is shadowed by `DELETE /items/:id` because the latter is registered first with no path constraint. Express matches `/items/selected` against `:id`. Port needs to either reorder or change paths.

4. **`order.created` payload doesn't include `productId`/`buyerId` for live placeOrder**: inventory worker therefore can't decrement stock for live-flow orders. Bug already in JS; preserve or fix during port.

5. **DeepSeek hardcoded API key fallback** in `services/deepseek.service.js`. Don't carry over.

6. **MoMo/VNPay fallback credentials in `config/payment.js`** are sandbox keys baked into source. Don't carry over.

7. **Order id reverse-extraction** in VNPay return: parses `vnp_OrderInfo` by stripping the literal string `'Thanh toan don hang '`. Any change to the prefix breaks reconciliation.

8. **ZaloPay `appTransId` format**: code uses `YYYYMMDD<8hex>` (8 + 8 = 16 chars), but ZaloPay spec expects `yyMMdd_<...>` style. May still work in sandbox but worth checking.

9. **Token route silently downgrades** publisher â†’ subscriber if the JWT role isn't seller/admin. No 403 â€” clients can't tell.

10. **Refresh token implementation is opaque random bytes**, NOT a JWT, despite `signRefreshToken`/`verifyRefreshToken` being exported (they're dead code). Don't port them â€” they'd cause confusion.

11. **Welcome email is sent on OTP verify**, not on register, because `user.registered` is published in `verifyEmailOtp`. Document this.

12. **Live session coupon upsert by code**: `insertSessionCoupons` does `upsert(rows, {onConflict: 'code', ignoreDuplicates: false})` â€” this means starting a new live session with an existing coupon code **reassigns ownership** of that coupon to the new session/seller. Likely unintended.

13. **`category_id` vs M2M**: `category.repository.countProductsByCategory` queries a nonexistent column. The "products still using this category" guard on category delete is effectively bypassed.

14. **Cache invalidation pattern uses Redis SCAN** with `MATCH` â€” fine on small data but iterates the entire keyspace. In Go, prefer keeping a set of cache keys per resource.

15. **Rate limiter is per-path** (`rl:{req.path}:{id}`). Param-heavy paths (`/api/live/:id/chat`) produce a different counter per `:id` value â€” likely intentional per-session, but check if you want per-route grouping in Go.

16. **`AccessToken#toJwt` is async** in `livekit-server-sdk` v2 â€” the Go port should use `github.com/livekit/protocol/auth` similarly.

17. **`order-status.worker` and `payment.service.markPaidAndNotify` both update orders** on `payment.success`. Idempotent but duplicate work. Pick one source of truth in Go.

18. **`POST /api/live/:id/like` has no auth** â€” anyone with a session id can spam like-count. Either fix in port or replicate behavior.

19. **`crypto.randomInt(100000, 999999)` for OTP** â€” upper bound is exclusive so OTPs are in `[100000, 999999)` i.e. `999999` never appears. Match in Go if you care about parity.

20. **Cookie path is `/api/auth`** â€” the refresh_token cookie only ships to those endpoints. Don't widen the path in the port.

21. **`config/auth.js` throws on missing JWT secrets at import time** â€” boot fails fast. `config/services.js` does NOT throw on missing Supabase URL/key; runtime queries will fail mysteriously. Port should validate all required env at boot.

22. **`shop_id` resolution everywhere is messy**: `:shopId`/`:id` parameters may be `shops.id`, `seller_id` (profile UUID), or shop slug. `findShopBySlug` tries all three. Coupon `shop/:shopId`, follow/unfollow, getShopBySlug all use this fuzziness. Decide if you want strict typing in Go.

23. **Sensitive routes audit log** writes only `/api/auth/`, `/api/orders`, `/api/upload` at `info` level; all others are silent unless â‰¥400. Other security events go through `logSecurityEvent` which is a `warn` log with `[SECURITY]` prefix.

24. **Soft-delete column variation**: `products.status='deleted'` vs `profiles.status='deleted'` (string sentinel, no `deleted_at`). Variants use **hard** delete.

25. **No idempotency keys on payment init** â€” re-calling `POST /api/payment/momo` for the same order generates a new MoMo `requestId` each time but the order DB row stays the same. MoMo may reject duplicate `requestId`s on their side; otherwise multiple payUrls float around.

26. **`cart.checkout.service` accepts `discountAmount` from client** for non-validated shop coupons up to `subtotal`. Treat as known risk in the port.

27. **DeepSeek prompt construction** in `live.controller` overrides client-provided `productName`/`category` if the live session has products in DB â€” important for caching/test parity.

28. **`live_session_products.id` is used as a quasi-`variant_id` in cart**, AND as the `product_id` in `live_orders`. So `live_orders.product_id` is a FK to `live_session_products.id`, not `products.id`. Easy to miss.

29. **The Express app exports `module.exports = app`** at the end of `index.js` â€” supertest-friendly. Tests live under `tests/unit` and `tests/integration` per `package.json` scripts but no test files are present in `backend/src`.

30. **Workers must run in separate processes** (separate `node` invocations) â€” they all call `rabbitmq.connect()` independently. Plan for separate Go binaries or a single multi-goroutine consumer.

---

## 8. Quick file map (absolute paths)

- Entry: `C:\Users\Admin\Tropia\backend\src\index.js`
- Config: `C:\Users\Admin\Tropia\backend\src\config\{index,server,auth,payment,services}.js`
- Env template: `C:\Users\Admin\Tropia\backend\.env.example`
- Lib (infra): `C:\Users\Admin\Tropia\backend\src\lib\{supabase,redis,rabbitmq,cloudinary,email,passport,logger}.js`
- Errors: `C:\Users\Admin\Tropia\backend\src\errors\AppError.js`
- Middleware: `C:\Users\Admin\Tropia\backend\src\middleware\{auth,errorHandler,security}.js`
- Routes: `C:\Users\Admin\Tropia\backend\src\routes\{auth,live,token,orders,upload,categories,shops,products,payment,coupons,cart}.js`
- Controllers: `C:\Users\Admin\Tropia\backend\src\controllers\{auth,live,order,product,coupon,cart,shop,category,payment}.controller.js`
- Services: `C:\Users\Admin\Tropia\backend\src\services\{auth,live,order,product,coupon,shop,category,payment,cart.checkout,deepseek}.service.js`
- Repositories: `C:\Users\Admin\Tropia\backend\src\repositories\{auth,live,order,product,coupon,cart,shop,category}.repository.js`
- Workers: `C:\Users\Admin\Tropia\backend\src\workers\{inventory,order-status,notification}.worker.js`
