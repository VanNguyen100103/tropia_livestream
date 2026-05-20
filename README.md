# Tropia

Vietnamese fresh grocery app with Shopee-Live-style livestream shopping.

```
Tropia/
├── frontend/   Flutter app (Android, iOS, Web, desktop)
├── backend/    Go API (Gin + SRS + Postgres + Redis + R2)
├── infra/      Docker Compose stack for local development
├── k8s/        Kubernetes manifests for production
├── docs/       Documentation
└── CLAUDE.md   Project overview / AI agent guide
```

## Stack

- **Media**: SRS 5 (RTMP / SRT / WHIP ingest, LL-HLS / WHEP playback) + FFmpeg + NVENC
- **Backend**: Go 1.26 (Gin / pgx / go-redis / JWT / OAuth2)
- **Storage**: Cloudflare R2 (S3-compatible)
- **Database**: PostgreSQL (Supabase managed or self-hosted in K8s)
- **Cache / Events**: Redis 7 (cache, locks, rate limits, Streams)
- **Frontend**: Flutter 3.x
- **Deploy**: Kubernetes
- **Observability**: Prometheus + Grafana
- **CDN**: Cloudflare

## Quick start (local dev)

```bash
# 1. Start infra (Postgres + Redis + SRS via Docker Compose)
cd infra && docker compose up -d

# 2. Configure backend
cp backend/.env.example backend/.env.development
# Edit backend/.env.development with your secrets (Supabase / R2 / OAuth / payment)

# 3. Run Go backend
cd backend && go run ./cmd/api
# → http://localhost:3000/health

# 4. Run Flutter app
cd frontend && flutter pub get && flutter run
```

See [CLAUDE.md](CLAUDE.md) for the full project overview.

## Production deploy

Kubernetes manifests in [k8s/](k8s/). See [k8s/README.md](k8s/README.md)
for deploy instructions.

## License

Private — Tropia internal project.
