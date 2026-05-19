'use strict';

// Mock tất cả infra trước khi require app
jest.mock('../../src/lib/supabase', () => require('../mocks/supabase.mock'));
jest.mock('../../src/lib/redis',    () => require('../mocks/redis.mock'));
jest.mock('../../src/lib/rabbitmq', () => ({ publish: jest.fn().mockResolvedValue(undefined), connect: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../src/middleware/security', () => ({
  helmetConfig:    () => (_, __, next) => next(),
  requestId:       () => (_, __, next) => next(),
  sanitizeInput:   () => (_, __, next) => next(),
  requestSizeGuard:() => (_, __, next) => next(),
  auditLog:        () => (_, __, next) => next(),
  logSecurityEvent: jest.fn(),
}));

const request = require('supertest');
const bcrypt  = require('bcryptjs');
const app     = require('../../src/index');
const supabaseMock = require('../mocks/supabase.mock');

// ── Fixtures ─────────────────────────────────────────────────────────────────

const HASH = bcrypt.hashSync('Password1!', 1);

function makeDBUser(overrides = {}) {
  return {
    id:                    'uid-001',
    email:                 'user@tropia.vn',
    name:                  'Test User',
    role:                  'buyer',
    status:                'active',
    password_hash:         HASH,
    failed_login_attempts: 0,
    locked_until:          null,
    avatar_url:            null,
    ...overrides,
  };
}

// ── POST /api/auth/register ───────────────────────────────────────────────────

describe('POST /api/auth/register', () => {
  beforeEach(() => supabaseMock.__reset());

  it('201 khi đăng ký hợp lệ', async () => {
    // emailExists (maybeSingle) → null; createProfile (insert .single) → user
    supabaseMock.__setSelectQueue(null);           // emailExists → null
    supabaseMock.__setInsertResult(makeDBUser());  // createProfile

    const res = await request(app)
      .post('/api/auth/register')
      .send({ email: 'new@tropia.vn', password: 'Password1!', fullName: 'New User' });

    expect(res.status).toBe(201);
    expect(res.body.user).toBeDefined();
  });

  it('422 khi password quá ngắn', async () => {
    const res = await request(app)
      .post('/api/auth/register')
      .send({ email: 'x@x.com', password: 'short', fullName: 'X' });

    expect(res.status).toBe(422);
  });

  it('422 khi email không hợp lệ', async () => {
    const res = await request(app)
      .post('/api/auth/register')
      .send({ email: 'not-an-email', password: 'Password1!', fullName: 'X' });

    expect(res.status).toBe(422);
  });

  it('422 khi password không có chữ hoa', async () => {
    const res = await request(app)
      .post('/api/auth/register')
      .send({ email: 'x@x.com', password: 'password1!', fullName: 'X' });

    expect(res.status).toBe(422);
  });

  it('409 khi email đã tồn tại', async () => {
    supabaseMock.__setSelectResult(makeDBUser()); // emailExists → có data

    const res = await request(app)
      .post('/api/auth/register')
      .send({ email: 'user@tropia.vn', password: 'Password1!', fullName: 'Existing User' });

    expect(res.status).toBe(409);
  });
});

// ── POST /api/auth/login ──────────────────────────────────────────────────────

describe('POST /api/auth/login', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 + accessToken khi credentials đúng', async () => {
    // findProfileByEmail (maybeSingle) → user; clearLoginFailure (update) → ok; insertRefreshToken (insert) → ok
    supabaseMock.__setSelectQueue(makeDBUser()); // findProfileByEmail
    supabaseMock.__setUpdateResult(makeDBUser()); // clearLoginFailure
    supabaseMock.__setInsertResult({ id: 'rt-001' }); // insertRefreshToken

    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'user@tropia.vn', password: 'Password1!' });

    expect(res.status).toBe(200);
    expect(res.body.accessToken).toBeTruthy();
    expect(res.body.user.email).toBe('user@tropia.vn');
  });

  it('401 khi sai mật khẩu', async () => {
    supabaseMock.__setSelectQueue(makeDBUser()); // findProfileByEmail
    supabaseMock.__setUpdateResult(makeDBUser());

    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'user@tropia.vn', password: 'WrongPass!' });

    expect(res.status).toBe(401);
  });

  it('401 khi user không tồn tại', async () => {
    supabaseMock.__setSelectResult(null);

    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'ghost@x.com', password: 'Password1!' });

    expect(res.status).toBe(401);
  });

  it('422 khi thiếu email', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ password: 'Password1!' });

    expect(res.status).toBe(422);
  });
});

// ── GET /api/auth/me ──────────────────────────────────────────────────────────

describe('GET /api/auth/me', () => {
  const { makeToken } = require('../helpers/token');

  it('200 khi có valid Bearer token', async () => {
    const token = makeToken({ id: 'uid-001' });
    supabaseMock.__setSelectResult(makeDBUser());

    const res = await request(app)
      .get('/api/auth/me')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.id).toBe('uid-001');
  });

  it('401 khi không có token', async () => {
    const res = await request(app).get('/api/auth/me');
    expect(res.status).toBe(401);
  });

  it('401 khi token không hợp lệ', async () => {
    const res = await request(app)
      .get('/api/auth/me')
      .set('Authorization', 'Bearer invalid.token.here');

    expect(res.status).toBe(401);
  });
});

// ── POST /api/auth/forgot-password ───────────────────────────────────────────

describe('POST /api/auth/forgot-password', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 dù email không tồn tại (anti-enumeration)', async () => {
    supabaseMock.__setSelectResult(null);

    const res = await request(app)
      .post('/api/auth/forgot-password')
      .send({ email: 'ghost@x.com' });

    expect(res.status).toBe(200);
  });

  it('200 khi email tồn tại', async () => {
    supabaseMock.__setSelectQueue(makeDBUser()); // findProfileByEmail
    supabaseMock.__setUpdateResult(makeDBUser()); // setPasswordResetToken

    const res = await request(app)
      .post('/api/auth/forgot-password')
      .send({ email: 'user@tropia.vn' });

    expect(res.status).toBe(200);
  });
});
