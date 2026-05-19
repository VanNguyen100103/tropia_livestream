'use strict';

/**
 * Mock Redis cho integration tests.
 * Dùng in-memory Map thay vì kết nối thật.
 */

const store = new Map();
const releaseMock = jest.fn().mockResolvedValue(1);

const redisMock = {
  get:    jest.fn(async (key) => store.get(key) ?? null),
  set:    jest.fn(async (key, val) => { store.set(key, val); return 'OK'; }),
  setex:  jest.fn(async (key, _ttl, val) => { store.set(key, val); return 'OK'; }),
  del:    jest.fn(async (key) => { store.delete(key); return 1; }),
  eval:   jest.fn().mockResolvedValue(1),  // lock always succeeds
  scan:   jest.fn().mockResolvedValue(['0', []]),
  zadd:   jest.fn().mockResolvedValue(1),
  zcard:  jest.fn().mockResolvedValue(0),
  zremrangebyscore: jest.fn().mockResolvedValue(0),
  pexpire: jest.fn().mockResolvedValue(1),
  on:     jest.fn(),
  quit:   jest.fn().mockResolvedValue(undefined),
};

module.exports = {
  getRedis:    jest.fn(() => redisMock),
  cacheAside:  jest.fn(async (_key, loader) => loader()),
  invalidatePattern: jest.fn().mockResolvedValue(undefined),
  acquireLock: jest.fn().mockResolvedValue(releaseMock),
  rateLimiter: () => (_req, _res, next) => next(),
  __store:     store,
  __redisMock: redisMock,
};
