# Tropia – Live Shopping Platform

Ứng dụng mua sắm thực phẩm tươi sống Việt Nam với tính năng livestream bán
hàng (Shopee Live style). Stack production-grade trên SRS + Go + Postgres
+ Redis + Cloudflare R2 + Kubernetes.

## Cấu trúc monorepo

```
Tropia/
├── frontend/        Flutter app (Android / iOS / Web / Windows / macOS / Linux)
├── backend/         Go API (Gin + pgx + SRS integration)
├── infra/           Docker Compose stack cho local dev
├── k8s/             Kubernetes manifests cho production
├── docs/            Documentation
└── CLAUDE.md        This file
```

## Stack

| Layer | Tech |
|---|---|
| Frontend | Flutter 3.x + Provider + Dio + video_player/chewie (HLS) |
| Backend | Go 1.26 + Gin + pgx + go-redis + JWT + OAuth2 (Google) |
| Media server | SRS 5 (RTMP / SRT / WHIP ingest, LL-HLS / WHEP playback) |
| Database | PostgreSQL (Supabase managed, or local Postgres in K8s) |
| Cache / Events | Redis 7 (cache, distributed lock, sliding-window rate limit, Streams pub/sub) |
| Object storage | Cloudflare R2 (S3 SDK) for VOD + image uploads |
| Payment | MoMo + VNPay + ZaloPay (HMAC) |
| AI | DeepSeek (live AI suggestions, auto-reply, sentiment analysis) |
| Email | SMTP (Gmail App Password) |
| Deploy | Kubernetes (StatefulSet for Postgres, Deployment + HPA for backend) |
| Observability | Prometheus /metrics + Grafana datasource |

## Local development

### 1. Start infra (Postgres + Redis + SRS)

```bash
cd infra
docker compose up -d
```

Postgres → host port `5433` (5432 conflicts with native pg on this machine).
Redis → host port `6380`. SRS → 1935 (RTMP) / 8080 (HLS) / 1985 (HTTP API).

### 2. Start Go backend

```bash
cd backend
go run ./cmd/api
```

Reads `backend/.env.development` (gitignored). Listens on `:3000`.
Health: `curl http://localhost:3000/health`.

### 2b. Database migrations

Schema is managed by [golang-migrate](https://github.com/golang-migrate/migrate)
in `backend/migrations/`. The Docker Compose Postgres also auto-runs
`infra/postgres/init.sql` (a copy of migration 0001) on first volume init,
so for local dev you usually don't need to run migrations manually.

For Supabase / production / when you add migration 0002+:

```bash
cd backend
# First time pointing at Supabase that already has the initial schema:
.\scripts\migrate.ps1 force 1     # Windows
make migrate-force ver=1          # Unix

# Apply any pending migrations
.\scripts\migrate.ps1 up          # Windows
make migrate-up                   # Unix

# Add a new schema change
.\scripts\migrate.ps1 create add_phone_to_profiles
# → edits 0002_add_phone_to_profiles.up.sql + .down.sql, then `migrate-up`
```

See `backend/migrations/README.md` for full workflow.

### 2c. Seed test data

After the schema is in place, populate the DB with deterministic
fixtures (1 admin + 1 seller + 1 buyer + 1 shop + 3 categories + 2 products
+ 1 live session). Idempotent — safe to re-run.

```bash
cd backend
.\scripts\seed.ps1                   # Windows
make seed                            # Unix
# or directly:
go run ./cmd/seed
```

All seed accounts share password `Password123`. See `cmd/seed/main.go`
for the full list of fixtures.

### 3. Start Flutter

```bash
cd frontend
flutter pub get
flutter run
```

Android emulator targets `http://10.0.2.2:3000` for the backend.
Physical device on same LAN → set the LAN IP of your host machine.

## Key endpoints (Go backend)

| Path | Auth | Description |
|---|---|---|
| `POST /api/auth/register` | none | Register + emit OTP to Redis |
| `POST /api/auth/verify-otp` | none | Verify email OTP |
| `POST /api/auth/login` | none | bcrypt + JWT issuance + refresh cookie |
| `POST /api/auth/refresh` | cookie/body | Refresh rotation + reuse detection |
| `GET /api/auth/google` | none | Google OAuth2 redirect |
| `GET /api/live/streams` | none | List active streams |
| `POST /api/live/streams` | seller | Create stream, returns RTMP/WHIP/SRT publish URLs |
| `GET /api/live/streams/:id/playback` | none | Returns HLS / FLV / WHEP playback URLs |
| `POST /api/live/streams/:id/ai-suggestions` | yes | DeepSeek viewer questions |
| `POST /api/srs/on_publish` | SRS only | Webhook from SRS when stream starts |
| `POST /api/payment/momo` / `/vnpay` / `/zalopay` | yes | Init payment |
| `GET /health` | none | Liveness probe |
| `GET /metrics` | none | Prometheus scrape endpoint |

## Stream flow

1. Seller calls `POST /api/live/streams` → backend creates session, returns
   `{publish: {rtmp, whip, srt}}`.
2. Seller pushes media via OBS / Larix Broadcaster to the RTMP URL.
3. SRS calls `POST /api/srs/on_publish` → backend marks stream as live.
4. Viewer calls `GET /api/live/streams/:id/playback` → gets HLS URL.
5. Flutter app plays via `HlsViewer` (video_player + chewie).
6. SRS DVR records to FLV → backend uploads to R2 on `on_dvr`.

## Flutter frontend (frontend/lib)

```
lib/
├── main.dart
├── core/
│   ├── config/app_config.dart      (backendUrl, API prefixes)
│   ├── constants/app_constants.dart (AppColors, AppStrings, AppSizes, AppUrls)
│   ├── services/auth_service.dart  (Dio + JWT interceptor)
│   ├── theme/app_theme.dart
│   └── utils/logger.dart
└── features/
    ├── main/                       Bottom nav 5 tabs
    ├── home/                       Tab Trang chủ
    ├── live/                       Live & Video module
    │   ├── data/live_repository.dart   (calls Go backend)
    │   ├── models/live_stream_model.dart
    │   ├── providers/live_provider.dart (Provider state)
    │   ├── services/srs_service.dart  (typed SRS endpoint client)
    │   ├── services/ai_suggestion_service.dart
    │   ├── screens/
    │   │   ├── live_tab_screen.dart
    │   │   ├── live_stream_screen.dart  (HLS viewer + overlays)
    │   │   ├── live_host_screen.dart    (publish info for OBS)
    │   │   └── live_setup_screen.dart
    │   └── widgets/
    │       ├── hls_viewer.dart          (video_player + chewie)
    │       ├── rtmp_publish_info.dart   (copy-able RTMP/WHIP/SRT URLs)
    │       ├── live_chat_widget.dart
    │       ├── live_product_card_widget.dart
    │       ├── live_actions_widget.dart
    │       └── ...
    ├── shop/                       Shop CRUD + follow
    ├── product/                    Product browse + detail
    ├── cart/                       Cart + checkout
    ├── order/                      Order history
    ├── upload/                     Image upload to R2
    └── user/                       Auth screens (login, register, OTP, profile)
```

State management: **Provider** (ChangeNotifier). `LiveProvider` is mounted
at `MainScreen` so the entire Live tab tree shares one instance.

## Conventions

- **No mock data in lib/**. All data comes from the Go backend via
  `LiveRepository` / `AuthService.authorizedDio()`. The 6 fake streams
  (Con Cưng, Lạc Yên, ...) were removed when the backend was wired up.
- **No hardcoded strings/colors** — use `AppStrings.xxx`, `AppColors.xxx`.
- **Log user events** via `AppLogger.logUserEvent(action, context, metadata)`.
- **HLS player** is `HlsViewer` (`video_player` + `chewie`). LiveKit /
  Agora code has been removed (Phase 16). For in-app camera publishing,
  see `lib/features/live/FLUTTER_PORT_TODO.md`.

## Production deploy

See `k8s/README.md` for full instructions. Summary:

```bash
kubectl apply -f k8s/namespace.yaml
cp k8s/secrets.example.yaml k8s/secrets.yaml && $EDITOR k8s/secrets.yaml
kubectl apply -f k8s/secrets.yaml
kubectl create configmap postgres-init \
  --from-file=init.sql=infra/postgres/init.sql -n tropia
docker build -t registry.tropia.vn/backend:v1.0.0 backend/
docker push registry.tropia.vn/backend:v1.0.0
kubectl apply -f k8s/
```

Backend exposes Prometheus metrics at `/metrics`. The
`prometheus.io/scrape` annotation on the backend Deployment lets the
included Prometheus pick them up automatically.

## Security

- Real `.env.*` files (dev/staging/prod) are gitignored. Only
  `.env.example` is committed.
- `k8s/secrets.yaml` is gitignored. Only `secrets.example.yaml` is
  committed.
- JWT secrets must be ≥ 32 bytes (config loader enforces this).
- Cookies use `SameSite=Strict`, `Secure` in release mode, path
  `/api/auth`.
- BOLA defense returns 404 not 403 (mirrors Node.js parity).
- Rate limits: login 5/min, register 3/5min, payment 10/min — all
  fail-closed via Redis sliding-window Lua script.

## Audit / migration history

See `backend/AUDIT.md` for the full 800-line audit of the original
Node.js + Supabase backend that was ported to this Go service across 20
phases (`git log --oneline`). Notable preserved quirks (documented in
the audit):

- `live_orders.unit_price` is overloaded — per-item for live placeOrder,
  subtotal for cart checkout.
- `cart_items.variant_id` holds either `product_variants.id` OR
  `live_session_products.id`.
- `live_sessions.agora_channel` is now the SRS stream key (field name
  kept for back-compat).
