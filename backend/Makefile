# Tropia backend — common development tasks
#
# Requires:
#   - go 1.26+
#   - golang-migrate (https://github.com/golang-migrate/migrate/releases)
#     On Windows: scoop install migrate  OR  choco install migrate
#     On macOS:   brew install golang-migrate
#     On Linux:   apt install golang-migrate  (or download release binary)

# Load DATABASE_URL from .env.development if present
ifneq (,$(wildcard .env.development))
    include .env.development
    export
endif

MIGRATIONS_DIR := migrations

.PHONY: help
help:
	@echo "Tropia backend — make targets"
	@echo "  make run                  — go run ./cmd/api"
	@echo "  make build                — build api binary to ./api"
	@echo "  make tidy                 — go mod tidy"
	@echo "  make seed                 — populate DB with deterministic test data"
	@echo "  make migrate-up           — apply all pending migrations"
	@echo "  make migrate-down         — rollback last migration"
	@echo "  make migrate-down-all     — rollback ALL migrations (drops everything)"
	@echo "  make migrate-status       — show current migration version"
	@echo "  make migrate-create name=add_phone_to_profiles  — create new migration files"
	@echo "  make migrate-force ver=1  — mark a specific version (recover from dirty state)"
	@echo ""
	@echo "DATABASE_URL is read from .env.development."

.PHONY: run build tidy seed
run:
	go run ./cmd/api

build:
	CGO_ENABLED=0 go build -ldflags="-s -w" -o api ./cmd/api

tidy:
	go mod tidy

seed:
	go run ./cmd/seed

# ── Migrations ───────────────────────────────────────────────────────────────

.PHONY: migrate-up migrate-down migrate-down-all migrate-status migrate-create migrate-force

migrate-up:
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" up

migrate-down:
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" down 1

migrate-down-all:
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" down -all

migrate-status:
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" version

migrate-create:
	@if [ -z "$(name)" ]; then echo "Usage: make migrate-create name=add_phone_to_profiles"; exit 1; fi
	migrate create -ext sql -dir $(MIGRATIONS_DIR) -seq $(name)

migrate-force:
	@if [ -z "$(ver)" ]; then echo "Usage: make migrate-force ver=1"; exit 1; fi
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" force $(ver)
