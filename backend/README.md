# Tropia Backend (Go)

Go backend for Tropia Live - replaces the Node.js backend with a Go service that integrates with SRS for media handling.

## Stack

| Layer | Tech |
|---|---|
| Language | Go 1.23+ |
| HTTP | Gin |
| DB | Postgres (pgx) |
| Cache / Pub-Sub | Redis |
| Auth | JWT (HMAC-SHA256) + OAuth2 |
| Media server | SRS (separate container, see `infra/`) |
| Storage | Cloudflare R2 (S3-compatible) |

## Layout

```
backend-go/
├── cmd/api/main.go         # Entry point
├── internal/
│   ├── config/             # Env config loader
│   ├── database/           # Postgres + Redis pool
│   ├── auth/               # JWT + middleware + handlers
│   ├── live/               # Stream model/repo/service/handler
│   ├── srs/                # SRS webhook handler
│   ├── chat/               # Chat REST + Redis pub/sub
│   ├── httpx/              # HTTP helpers
│   └── storage/            # R2/S3 client
└── migrations/             # SQL migrations (run via psql)
```

## Run locally

1. Start infra (Postgres + Redis + SRS):
   ```bash
   cd ../infra
   docker compose up -d
   ```

2. Copy env:
   ```bash
   cp .env.example .env.development
   # Edit .env.development - at minimum generate JWT secrets:
   # node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
   ```

3. Install deps & run:
   ```bash
   go mod tidy
   go run ./cmd/api
   ```

   API will be at http://localhost:3000

## Endpoints

| Method | Path | Auth | Role |
|---|---|---|---|
| POST | /api/auth/register | - | - |
| POST | /api/auth/login | - | - |
| POST | /api/auth/refresh | - | - |
| GET | /api/auth/me | JWT | any |
| GET | /api/live/streams | - | - |
| GET | /api/live/streams/:id/playback | - | - |
| POST | /api/live/streams | JWT | seller/admin |
| GET | /api/live/streams/:id/publish | JWT | owner/admin |
| GET | /api/live/streams/:id/messages | - | - |
| POST | /api/live/streams/:id/messages | JWT | any |
| POST | /api/srs/on_publish | - (SRS) | - |
| POST | /api/srs/on_unpublish | - (SRS) | - |
| POST | /api/srs/on_play | - (SRS) | - |
| POST | /api/srs/on_stop | - (SRS) | - |
| POST | /api/srs/on_dvr | - (SRS) | - |

## Live stream flow

1. **Seller creates stream** → `POST /api/live/streams` → returns `{stream, publish: {rtmp, whip, srt}}`
2. **Seller pushes media** to SRS using the returned `publish.rtmp` URL (e.g. from OBS) or `publish.whip` (from Flutter)
3. **SRS calls webhook** `POST /api/srs/on_publish` → backend marks stream as `live`
4. **Viewer fetches playback URL** → `GET /api/live/streams/:id/playback` → returns `{playback: {hls, flv, whep}}`
5. **Viewer plays HLS** using `playback.hls` URL in `video_player` / `flutter_vlc_player` / native HLS
6. **Seller stops** → SRS calls `on_unpublish` → backend marks stream as `ended`
7. **SRS finishes DVR recording** → `on_dvr` → backend triggers FFmpeg job to remux FLV → MP4/HLS, upload to R2
