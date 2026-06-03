package httpx

import (
	"log/slog"
	"os"
)

func NewLogger(env string) *slog.Logger {
	var handler slog.Handler
	if env == "production" {
		handler = slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})
	} else {
		handler = slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelDebug})
	}
	l := slog.New(handler)
	// Wire as the package-level default so libraries (and our own code that
	// uses `slog.Default()` — e.g. the bot reply path in internal/live)
	// log through the same formatter + level instead of slog's built-in
	// stderr handler.
	slog.SetDefault(l)
	return l
}
