# Multi-stage build for Tropia Go backend
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Cache deps layer
COPY go.mod go.sum ./
RUN go mod download

# Build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/api ./cmd/api

# Runtime
FROM alpine:3.20
RUN apk --no-cache add ca-certificates tzdata
WORKDIR /app
COPY --from=builder /out/api /app/api
EXPOSE 3000
ENV PORT=3000
ENTRYPOINT ["/app/api"]
