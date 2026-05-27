# Multi-stage build for Tropia Go backend.
# Pin the toolchain so docker builds reproduce go.mod's `go 1.26.3`.
# Produces a single image with all 4 binaries baked in:
#   /app/api      → HTTP server (default ENTRYPOINT)
#   /app/worker   → background event consumer (override via `command:`)
#   /app/migrate  → DB migration runner
#   /app/seed     → fixture loader
FROM golang:1.26-alpine AS builder

WORKDIR /app

# Cache deps layer
COPY go.mod go.sum ./
RUN go mod download

# Build all 4 binaries in one stage so they share the same module download.
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/api      ./cmd/api && \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/worker   ./cmd/worker && \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/migrate  ./cmd/migrate && \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/seed     ./cmd/seed

# Runtime
FROM alpine:3.20
RUN apk --no-cache add ca-certificates tzdata && \
    addgroup -S app -g 10001 && \
    adduser  -S app -G app -u 10001 -h /app
WORKDIR /app
COPY --from=builder --chown=app:app /out/api      /app/api
COPY --from=builder --chown=app:app /out/worker   /app/worker
COPY --from=builder --chown=app:app /out/migrate  /app/migrate
COPY --from=builder --chown=app:app /out/seed     /app/seed
# Migrations folder is needed at runtime by /app/migrate
COPY --chown=app:app migrations/ /app/migrations/
USER app:app
EXPOSE 3000
ENV PORT=3000
ENTRYPOINT ["/app/api"]
