package database

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// PoolConfig — knobs that should be tunable per environment without a
// recompile. Defaults chosen for "production behind PgBouncer
// transaction-mode": the app holds a fat pool, PgBouncer multiplexes
// onto far fewer actual Postgres backends. If you're not running
// PgBouncer, lower MaxConns to ~50 so Postgres itself isn't overwhelmed.
type PoolConfig struct {
	MaxConns        int32
	MinConns        int32
	MaxConnLifetime time.Duration
	MaxConnIdleTime time.Duration
	ConnectTimeout  time.Duration
}

func DefaultPoolConfig() PoolConfig {
	return PoolConfig{
		// 200 covers ~3k concurrent viewers polling /stats every 5s
		// (~600 req/s on the API, ~3 queries each = 1800 query/s, well
		// under the pool's checkout-and-release rate). Was 20 — that
		// blocked at ~250 concurrent viewers in the audit's math.
		MaxConns:        envInt32("POSTGRES_MAX_CONNS", 200),
		MinConns:        envInt32("POSTGRES_MIN_CONNS", 10),
		MaxConnLifetime: envDuration("POSTGRES_MAX_CONN_LIFETIME", time.Hour),
		MaxConnIdleTime: envDuration("POSTGRES_MAX_CONN_IDLE", 5*time.Minute),
		ConnectTimeout:  envDuration("POSTGRES_CONNECT_TIMEOUT", 5*time.Second),
	}
}

func NewPostgres(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	return NewPostgresWithConfig(ctx, dsn, DefaultPoolConfig())
}

func NewPostgresWithConfig(ctx context.Context, dsn string, pc PoolConfig) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("parse postgres dsn: %w", err)
	}
	cfg.MaxConns = pc.MaxConns
	cfg.MinConns = pc.MinConns
	cfg.MaxConnLifetime = pc.MaxConnLifetime
	cfg.MaxConnIdleTime = pc.MaxConnIdleTime
	cfg.ConnConfig.ConnectTimeout = pc.ConnectTimeout

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("create postgres pool: %w", err)
	}

	pingCtx, cancel := context.WithTimeout(ctx, pc.ConnectTimeout)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping postgres: %w", err)
	}

	return pool, nil
}

func envInt32(key string, fallback int32) int32 {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.ParseInt(v, 10, 32)
	if err != nil || n <= 0 {
		return fallback
	}
	return int32(n)
}

func envDuration(key string, fallback time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return fallback
	}
	return d
}
