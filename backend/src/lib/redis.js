'use strict';

const Redis  = require('ioredis');
const cfg    = require('../config');
const logger = require('./logger');
const { RateLimitError } = require('../errors/AppError');

let _client;

function getRedis() {
  if (!_client) {
    _client = new Redis({
      host:               cfg.redis.host,
      port:               cfg.redis.port,
      password:           cfg.redis.password,
      retryStrategy:      (times) => Math.min(times * 200, 5_000),
      maxRetriesPerRequest: 3,
      enableReadyCheck:   true,
      lazyConnect:        false,
    });
    _client.on('connect',      () => logger.info('Redis connected'));
    _client.on('error',   (e)  => logger.error({ err: e.message }, 'Redis error'));
    _client.on('reconnecting', () => logger.warn('Redis reconnecting...'));
  }
  return _client;
}

// ── Cache-aside ────────────────────────────────────────────────────────────────
async function cacheAside(key, loader, ttlSeconds = 300) {
  try {
    const redis  = getRedis();
    const cached = await redis.get(key);
    if (cached !== null) {
      try { return JSON.parse(cached); } catch { return cached; }
    }
    const value = await loader();
    if (value !== null && value !== undefined) {
      await redis.setex(key, ttlSeconds, JSON.stringify(value));
    }
    return value;
  } catch (err) {
    // Cache miss → fallback to loader (fail-open for reads)
    logger.warn({ err: err.message, key }, 'Redis cache miss – fallback to DB');
    return loader();
  }
}

async function invalidatePattern(pattern) {
  try {
    const redis  = getRedis();
    let   cursor = '0';
    do {
      const [next, keys] = await redis.scan(cursor, 'MATCH', pattern, 'COUNT', 100);
      cursor = next;
      if (keys.length) await redis.del(...keys);
    } while (cursor !== '0');
  } catch (err) {
    logger.warn({ err: err.message, pattern }, 'Redis invalidate failed');
  }
}

// ── Distributed lock (Redlock-lite) ───────────────────────────────────────────
const LOCK_SCRIPT = `
if redis.call('exists',KEYS[1])==0 then
  redis.call('set',KEYS[1],ARGV[1],'PX',ARGV[2])
  return 1
end return 0`;

const UNLOCK_SCRIPT = `
if redis.call('get',KEYS[1])==ARGV[1] then
  redis.call('del',KEYS[1]) return 1
end return 0`;

async function acquireLock(resource, { ttlMs = 5_000, retries = 3, retryDelayMs = 200 } = {}) {
  const redis = getRedis();
  const key   = `lock:${resource}`;
  const val   = require('uuid').v4();

  for (let i = 0; i <= retries; i++) {
    const ok = await redis.eval(LOCK_SCRIPT, 1, key, val, ttlMs);
    if (ok === 1) {
      return async () => redis.eval(UNLOCK_SCRIPT, 1, key, val);
    }
    if (i < retries) await new Promise(r => setTimeout(r, retryDelayMs * (i + 1)));
  }
  throw new Error(`Could not acquire lock: ${resource}`);
}

// ── Sliding-window rate limiter ────────────────────────────────────────────────
const RATE_SCRIPT = `
local key=KEYS[1] local window=tonumber(ARGV[1]) local limit=tonumber(ARGV[2]) local now=tonumber(ARGV[3])
redis.call('ZREMRANGEBYSCORE',key,'-inf',now-window)
local count=redis.call('ZCARD',key)
if count>=limit then return -1 end
redis.call('ZADD',key,now,now) redis.call('PEXPIRE',key,window)
return limit-count-1`;

/**
 * @param {object} opts
 * @param {number}   opts.max           – max requests per window
 * @param {number}   opts.windowMs      – window in ms
 * @param {Function} opts.keyFn         – (req) => string  (default: user id or IP)
 * @param {boolean}  opts.failClosed    – block when Redis is down (default: false)
 */
function rateLimiter({ max = 100, windowMs = 60_000, keyFn, failClosed = false } = {}) {
  return async (req, res, next) => {
    const redis = getRedis();
    const id    = keyFn ? keyFn(req) : (req.user?.id ?? req.ip ?? 'anon');
    const key   = `rl:${req.path}:${id}`;

    try {
      const rem = await redis.eval(RATE_SCRIPT, 1, key, windowMs, max, Date.now());
      res.setHeader('X-RateLimit-Limit',     max);
      res.setHeader('X-RateLimit-Remaining', Math.max(0, rem));
      res.setHeader('X-RateLimit-Reset',     Math.ceil((Date.now() + windowMs) / 1000));

      if (rem < 0) {
        res.setHeader('Retry-After', Math.ceil(windowMs / 1000));
        return next(new RateLimitError());
      }
      next();
    } catch (err) {
      logger.error({ err: err.message, key }, 'Rate limiter Redis error');
      // API4: sensitive endpoints fail-closed, others fail-open
      if (failClosed) return next(new RateLimitError('Service temporarily unavailable'));
      next();
    }
  };
}

module.exports = { getRedis, cacheAside, invalidatePattern, acquireLock, rateLimiter };
