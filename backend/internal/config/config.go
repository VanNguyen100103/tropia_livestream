package config

import (
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

// parseOrigins splits a comma-separated CORS_ORIGIN env into a list of
// trimmed origins. `*` is rejected silently — pairing wildcard origins
// with AllowCredentials=true is invalid per CORS spec, modern browsers
// will refuse the response. Callers must set a concrete origin list.
func parseOrigins(raw string) []string {
	out := make([]string, 0)
	for _, part := range strings.Split(raw, ",") {
		o := strings.TrimSpace(strings.TrimRight(part, "/"))
		if o == "" || o == "*" {
			continue
		}
		out = append(out, o)
	}
	return out
}

type Config struct {
	// Server
	Port    string
	GinMode string
	// CORSOrigins is a comma-separated whitelist set via CORS_ORIGIN.
	// Each origin must include scheme + host (no trailing slash). The
	// API rejects credentialed requests from origins not on this list.
	// Default empty means "no CORS" — set explicitly per environment.
	CORSOrigins []string

	// Database
	DatabaseURL string

	// Redis
	RedisAddr     string
	RedisPassword string
	RedisDB       int

	// JWT
	JWTAccessSecret  string
	JWTRefreshSecret string
	JWTAccessTTL     time.Duration
	JWTRefreshTTL    time.Duration

	// SRS
	SRSRtmpHost string
	SRSHlsHost  string
	SRSWhipHost string
	SRSApiHost  string

	// R2
	R2AccountID       string
	R2AccessKeyID     string
	R2SecretAccessKey string
	R2Bucket          string
	R2PublicURL       string

	// Google OAuth
	GoogleClientID     string
	GoogleClientSecret string
	GoogleRedirectURL  string
}

func Load() (*Config, error) {
	cfg := &Config{
		Port:    getEnv("PORT", "3000"),
		GinMode: getEnv("GIN_MODE", "debug"),
		// Empty/unset → dev fallback in cmd/api accepts any loopback
		// origin. Production MUST set this to the public domain(s) —
		// never `*`, since AllowCredentials=true makes that an invalid
		// CORS pair (browsers will reject it).
		CORSOrigins: parseOrigins(os.Getenv("CORS_ORIGIN")),

		DatabaseURL: mustEnv("DATABASE_URL"),

		RedisAddr:     getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword: getEnv("REDIS_PASSWORD", ""),
		RedisDB:       getEnvInt("REDIS_DB", 0),

		JWTAccessSecret:  mustEnv("JWT_ACCESS_SECRET"),
		JWTRefreshSecret: mustEnv("JWT_REFRESH_SECRET"),
		JWTAccessTTL:     getEnvDuration("JWT_ACCESS_TTL", 15*time.Minute),
		JWTRefreshTTL:    getEnvDuration("JWT_REFRESH_TTL", 7*24*time.Hour),

		SRSRtmpHost: getEnv("SRS_RTMP_HOST", "rtmp://localhost:1935"),
		SRSHlsHost:  getEnv("SRS_HLS_HOST", "http://localhost:8090"),
		SRSWhipHost: getEnv("SRS_WHIP_HOST", "http://localhost:1985"),
		SRSApiHost:  getEnv("SRS_API_HOST", "http://localhost:1985"),

		R2AccountID:       getEnv("R2_ACCOUNT_ID", ""),
		R2AccessKeyID:     getEnv("R2_ACCESS_KEY_ID", ""),
		R2SecretAccessKey: getEnv("R2_SECRET_ACCESS_KEY", ""),
		R2Bucket:          getEnv("R2_BUCKET", ""),
		R2PublicURL:       getEnv("R2_PUBLIC_URL", ""),

		GoogleClientID:     getEnv("GOOGLE_CLIENT_ID", ""),
		GoogleClientSecret: getEnv("GOOGLE_CLIENT_SECRET", ""),
		GoogleRedirectURL:  getEnv("GOOGLE_REDIRECT_URL", ""),
	}

	if len(cfg.JWTAccessSecret) < 32 {
		return nil, fmt.Errorf("JWT_ACCESS_SECRET must be at least 32 bytes")
	}
	if len(cfg.JWTRefreshSecret) < 32 {
		return nil, fmt.Errorf("JWT_REFRESH_SECRET must be at least 32 bytes")
	}

	// Production must use TLS to Postgres. Refuse to boot in release mode
	// if DATABASE_URL says sslmode=disable (or omits sslmode entirely,
	// since pgx then defaults to "prefer" which silently falls back to
	// cleartext when the server doesn't advertise TLS). Supabase and any
	// managed PG provider support sslmode=require out of the box.
	if cfg.GinMode == "release" {
		if err := requireDatabaseTLS(cfg.DatabaseURL); err != nil {
			return nil, err
		}
	}

	return cfg, nil
}

// requireDatabaseTLS rejects DATABASE_URLs that would connect to a
// Postgres on the public internet without TLS. In-cluster K8s service
// hosts (single-label like "postgres" or "pgbouncer", and any
// *.svc.cluster.local / *.cluster.local) are exempted because that
// traffic stays on the pod network — set up pgbouncer TLS if you want
// to harden that hop too, but it's not enforced here so the bundled
// K8s manifests keep working out of the box.
func requireDatabaseTLS(raw string) error {
	host := databaseHost(raw)
	if isInternalHost(host) {
		return nil
	}
	lower := strings.ToLower(raw)
	if strings.Contains(lower, "sslmode=disable") ||
		strings.Contains(lower, "sslmode=allow") ||
		strings.Contains(lower, "sslmode=prefer") {
		return fmt.Errorf("DATABASE_URL host %q is external; sslmode must be require / verify-ca / verify-full in release mode", host)
	}
	if !strings.Contains(lower, "sslmode=") {
		return fmt.Errorf("DATABASE_URL host %q is external; sslmode must be set explicitly (pgx defaults to 'prefer' which permits cleartext)", host)
	}
	return nil
}

func databaseHost(raw string) string {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return ""
	}
	return u.Hostname()
}

func isInternalHost(host string) bool {
	if host == "" {
		return false
	}
	if host == "localhost" || host == "127.0.0.1" || host == "::1" {
		return true
	}
	// Single-label hostnames (no dot) are K8s service names like
	// "postgres", "pgbouncer". Real public DBs always have a dotted FQDN.
	if !strings.Contains(host, ".") {
		return true
	}
	if strings.HasSuffix(host, ".svc.cluster.local") ||
		strings.HasSuffix(host, ".cluster.local") ||
		strings.HasSuffix(host, ".svc") {
		return true
	}
	return false
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		panic(fmt.Sprintf("required env var %s is not set", key))
	}
	return v
}

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}

func getEnvDuration(key string, fallback time.Duration) time.Duration {
	if v := os.Getenv(key); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return fallback
}
