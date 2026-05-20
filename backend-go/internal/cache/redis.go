package cache

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

type Cache struct {
	rds *redis.Client
}

func New(rds *redis.Client) *Cache {
	return &Cache{rds: rds}
}

func (c *Cache) Client() *redis.Client { return c.rds }

// Aside - cache-aside pattern. On miss, calls loader and stores result.
// Fail-open: on Redis error, falls through to loader.
func Aside[T any](ctx context.Context, c *Cache, key string, ttl time.Duration, loader func(context.Context) (T, error)) (T, error) {
	var zero T
	raw, err := c.rds.Get(ctx, key).Bytes()
	if err == nil {
		var out T
		if json.Unmarshal(raw, &out) == nil {
			return out, nil
		}
	}
	val, err := loader(ctx)
	if err != nil {
		return zero, err
	}
	if buf, err := json.Marshal(val); err == nil {
		_ = c.rds.Set(ctx, key, buf, ttl).Err()
	}
	return val, nil
}

// InvalidatePattern - SCAN + DEL by glob pattern (e.g. "live:sessions:*")
func (c *Cache) InvalidatePattern(ctx context.Context, pattern string) error {
	var cursor uint64
	for {
		keys, next, err := c.rds.Scan(ctx, cursor, pattern, 200).Result()
		if err != nil {
			return err
		}
		if len(keys) > 0 {
			if err := c.rds.Del(ctx, keys...).Err(); err != nil {
				return err
			}
		}
		if next == 0 {
			break
		}
		cursor = next
	}
	return nil
}

// ============================================================================
// Distributed lock (Redlock-lite via SET NX + Lua release)
// ============================================================================

var ErrLockHeld = errors.New("lock held by another process")

const releaseScript = `
if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("del", KEYS[1])
else
    return 0
end
`

type Lock struct {
	rds   *redis.Client
	key   string
	token string
}

type LockOptions struct {
	TTL         time.Duration
	Retries     int
	RetryDelay  time.Duration
}

func (c *Cache) AcquireLock(ctx context.Context, resource string, opts LockOptions) (*Lock, error) {
	if opts.TTL == 0 {
		opts.TTL = 5 * time.Second
	}
	if opts.Retries == 0 {
		opts.Retries = 5
	}
	if opts.RetryDelay == 0 {
		opts.RetryDelay = 200 * time.Millisecond
	}

	token := randomHex(16)
	key := "lock:" + resource

	for attempt := 0; attempt <= opts.Retries; attempt++ {
		ok, err := c.rds.SetNX(ctx, key, token, opts.TTL).Result()
		if err != nil {
			return nil, err
		}
		if ok {
			return &Lock{rds: c.rds, key: key, token: token}, nil
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(opts.RetryDelay * time.Duration(attempt+1)):
		}
	}
	return nil, ErrLockHeld
}

func (l *Lock) Release(ctx context.Context) error {
	if l == nil {
		return nil
	}
	return l.rds.Eval(ctx, releaseScript, []string{l.key}, l.token).Err()
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// ============================================================================
// Sliding-window rate limiter via ZSET
// ============================================================================

const rateLimitScript = `
local key = KEYS[1]
local now = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local limit = tonumber(ARGV[3])
local member = ARGV[4]

redis.call("ZREMRANGEBYSCORE", key, 0, now - window)
local count = redis.call("ZCARD", key)
if count >= limit then
    return 0
end
redis.call("ZADD", key, now, member)
redis.call("EXPIRE", key, math.ceil(window / 1000) + 1)
return 1
`

// Allow returns (allowed, error). On Redis error: respects failClosed.
func (c *Cache) Allow(ctx context.Context, key string, limit int, windowMs int64, failClosed bool) (bool, error) {
	now := time.Now().UnixMilli()
	member := fmt.Sprintf("%d:%s", now, randomHex(4))
	res, err := c.rds.Eval(ctx, rateLimitScript, []string{"rl:" + key}, now, windowMs, limit, member).Int()
	if err != nil {
		if failClosed {
			return false, err
		}
		return true, nil
	}
	return res == 1, nil
}
