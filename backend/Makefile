# Tropia backend — common development tasks.
#
# All `migrate-*` and `seed` targets use the in-tree binaries
# (cmd/migrate, cmd/seed). No external `migrate.exe` install required.

# Load DATABASE_URL from .env.development if present
ifneq (,$(wildcard .env.development))
    include .env.development
    export
endif

.PHONY: help
help:
	@echo "Tropia backend — make targets"
	@echo ""
	@echo "Run / build:"
	@echo "  make run                  — go run ./cmd/api"
	@echo "  make worker               — go run ./cmd/worker"
	@echo "  make build                — build ./api binary"
	@echo "  make build-all            — build all 4 binaries (api, worker, migrate, seed)"
	@echo "  make tidy                 — go mod tidy"
	@echo "  make seed                 — populate DB with deterministic test data"
	@echo ""
	@echo "Migrations (in-tree, no external binary needed):"
	@echo "  make migrate-up           — apply all pending migrations"
	@echo "  make migrate-down         — rollback last 1 migration"
	@echo "  make migrate-down-all     — rollback EVERYTHING"
	@echo "  make migrate-status       — show current version + dirty flag"
	@echo "  make migrate-create name=add_phone_to_profiles  — generate new SQL pair"
	@echo "  make migrate-force ver=1  — mark version (recover from dirty state)"
	@echo "  make migrate-goto ver=3   — migrate up or down to a specific version"
	@echo ""
	@echo "DATABASE_URL is read from .env.development."

# ── Run / build ──────────────────────────────────────────────────────────────

.PHONY: run worker build build-all tidy seed
run:
	go run ./cmd/api

worker:
	go run ./cmd/worker

build:
	CGO_ENABLED=0 go build -ldflags="-s -w" -o api ./cmd/api

build-all:
	CGO_ENABLED=0 go build -ldflags="-s -w" -o api      ./cmd/api
	CGO_ENABLED=0 go build -ldflags="-s -w" -o worker   ./cmd/worker
	CGO_ENABLED=0 go build -ldflags="-s -w" -o migrate  ./cmd/migrate
	CGO_ENABLED=0 go build -ldflags="-s -w" -o seed     ./cmd/seed

tidy:
	go mod tidy

seed:
	go run ./cmd/seed

# ── Migrations ───────────────────────────────────────────────────────────────

.PHONY: migrate-up migrate-down migrate-down-all migrate-status migrate-create migrate-force migrate-goto

migrate-up:
	go run ./cmd/migrate up

migrate-down:
	go run ./cmd/migrate down 1

migrate-down-all:
	go run ./cmd/migrate down all

migrate-status:
	go run ./cmd/migrate status

migrate-create:
	@if [ -z "$(name)" ]; then echo "Usage: make migrate-create name=add_phone_to_profiles"; exit 1; fi
	go run ./cmd/migrate create $(name)

migrate-force:
	@if [ -z "$(ver)" ]; then echo "Usage: make migrate-force ver=1"; exit 1; fi
	go run ./cmd/migrate force $(ver)

migrate-goto:
	@if [ -z "$(ver)" ]; then echo "Usage: make migrate-goto ver=3"; exit 1; fi
	go run ./cmd/migrate goto $(ver)
