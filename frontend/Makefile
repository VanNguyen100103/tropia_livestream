# =============================================================================
# Tropia Flutter — convenience targets
# =============================================================================
# Env config lives in env.<environment>.json (gitignored). Copy
# env.example.json to env.development.json / env.staging.json /
# env.production.json and fill in real values. Builds load these via
# `--dart-define-from-file`. Ad-hoc overrides for one build are still
# possible by passing `PROD_URL=...` / `PLACEHOLDER_URL=...` to make;
# they win over the file because later --dart-define args override
# earlier --dart-define-from-file ones.
#
# Usage:
#   make dev-mobile        # physical phone on Wi-Fi (script auto-detects LAN IP)
#   make dev-emu           # Android emulator (BACKEND_URL falls back to 10.0.2.2)
#   make dev-web           # Chrome (BACKEND_URL falls back to localhost)
#   make build-prod        # release APK from env.production.json
#   make build-staging     # release APK from env.staging.json
#
# One-off overrides:
#   make build-prod PROD_URL=https://api.example.com
#   make build-prod PLACEHOLDER_URL=https://cdn.example.com
# =============================================================================

# Empty by default — when set, layered as the LAST --dart-define so it
# overrides the matching key in env.<environment>.json.
PROD_URL        ?=
PLACEHOLDER_URL ?=

# OS-specific runner for the LAN-IP discovery script. Resolved at parse
# time by `make` itself (no shell if-statement), so it works under both
# cmd.exe (Windows GnuWin32 make) and bash (macOS/Linux).
ifeq ($(OS),Windows_NT)
    DEV_MOBILE_CMD := powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/dev-mobile.ps1
else
    DEV_MOBILE_CMD := bash scripts/dev-mobile.sh
endif

# Optional override args. Empty if the corresponding make var wasn't set.
# `$(if VAR,present,absent)` is GNU-make builtin and works on Windows GnuWin32.
PROD_URL_ARG        := $(if $(PROD_URL),--dart-define=BACKEND_URL=$(PROD_URL),)
PLACEHOLDER_URL_ARG := $(if $(PLACEHOLDER_URL),--dart-define=PLACEHOLDER_IMAGE_BASE_URL=$(PLACEHOLDER_URL),)

.PHONY: help dev-mobile dev-emu dev-web build-prod build-staging build-dev analyze clean

help:
	@echo "  make dev-mobile    — flutter run on physical device (auto LAN IP)"
	@echo "  make dev-emu       — flutter run on Android emulator"
	@echo "  make dev-web       — flutter run -d chrome"
	@echo "  make build-prod    — release APK from env.production.json"
	@echo "  make build-staging — release APK from env.staging.json"
	@echo "  make build-dev     — debug APK from env.development.json"
	@echo "  make analyze       — flutter analyze lib/"

dev-mobile:
	$(DEV_MOBILE_CMD)

dev-emu:
	flutter run -d emulator \
	  --dart-define-from-file=env.development.json \
	  $(PROD_URL_ARG) $(PLACEHOLDER_URL_ARG)

dev-web:
	flutter run -d chrome --web-port=5173 \
	  --dart-define-from-file=env.development.json \
	  $(PROD_URL_ARG) $(PLACEHOLDER_URL_ARG)

build-dev:
	flutter build apk --debug \
	  --dart-define-from-file=env.development.json \
	  $(PROD_URL_ARG) $(PLACEHOLDER_URL_ARG)

build-prod:
	flutter build apk --release \
	  --dart-define-from-file=env.production.json \
	  $(PROD_URL_ARG) $(PLACEHOLDER_URL_ARG)

build-staging:
	flutter build apk --release \
	  --dart-define-from-file=env.staging.json \
	  $(PROD_URL_ARG) $(PLACEHOLDER_URL_ARG)

analyze:
	flutter analyze lib

clean:
	flutter clean
