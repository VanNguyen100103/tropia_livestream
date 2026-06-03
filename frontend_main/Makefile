# =============================================================================
# Tropia main app (frontend_main) — convenience targets
# =============================================================================
# The main app reads its own backend from the bundled .env asset. The embedded
# livestream module (lib/livestream) reads BACKEND_URL via --dart-define and
# falls back to platform defaults (10.0.2.2 on Android emulator, localhost on
# web/desktop) when it isn't passed.
#
# Usage:
#   make dev-mobile   # physical phone on Wi-Fi (script auto-detects LAN IP)
#   make dev-emu      # Android emulator (live BACKEND_URL falls back to 10.0.2.2)
#   make dev-web      # Chrome (live BACKEND_URL falls back to localhost)
#   make build-dev    # debug APK
#   make analyze      # flutter analyze lib
# =============================================================================

# OS-specific runner for the LAN-IP discovery script. Resolved at parse time
# by `make` itself so it works under both cmd.exe (Windows make) and bash.
ifeq ($(OS),Windows_NT)
    DEV_MOBILE_CMD := powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/dev-mobile.ps1
else
    DEV_MOBILE_CMD := bash scripts/dev-mobile.sh
endif

.PHONY: help dev-mobile dev-emu dev-web build-dev analyze clean

help:
	@echo "  make dev-mobile  — flutter run on physical device (auto LAN IP)"
	@echo "  make dev-emu     — flutter run on Android emulator"
	@echo "  make dev-web     — flutter run -d chrome"
	@echo "  make build-dev   — debug APK"
	@echo "  make analyze     — flutter analyze lib"

dev-mobile:
	$(DEV_MOBILE_CMD)

dev-emu:
	flutter run -d emulator

dev-web:
	flutter run -d chrome --web-port=5173

build-dev:
	flutter build apk --debug

analyze:
	flutter analyze lib

clean:
	flutter clean
