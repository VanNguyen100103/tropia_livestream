'use strict';

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

const request      = require('supertest');
const app          = require('../../src/index');
const { bearerHeader } = require('../helpers/token');
const supabaseMock = require('../mocks/supabase.mock');

const BUYER_AUTH  = bearerHeader({ id: 'user-001', role: 'buyer' });
const SHOP_ID     = 'shop-uuid-001';

// ── POST /api/shops/:id/follow ────────────────────────────────────────────────

describe('POST /api/shops/:id/follow', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 + followed:true khi follow thành công', async () => {
    supabaseMock.__setInsertResult({ user_id: 'user-001', shop_id: SHOP_ID });

    const res = await request(app)
      .post(`/api/shops/${SHOP_ID}/follow`)
      .set(BUYER_AUTH);

    expect(res.status).toBe(200);
    expect(res.body.followed).toBe(true);
  });

  it('401 khi không có token', async () => {
    const res = await request(app).post(`/api/shops/${SHOP_ID}/follow`);
    expect(res.status).toBe(401);
  });
});

// ── DELETE /api/shops/:id/follow ──────────────────────────────────────────────

describe('DELETE /api/shops/:id/follow', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 + followed:false khi unfollow thành công', async () => {
    supabaseMock.__setDeleteResult(null);

    const res = await request(app)
      .delete(`/api/shops/${SHOP_ID}/follow`)
      .set(BUYER_AUTH);

    expect(res.status).toBe(200);
    expect(res.body.followed).toBe(false);
  });

  it('401 khi không có token', async () => {
    const res = await request(app).delete(`/api/shops/${SHOP_ID}/follow`);
    expect(res.status).toBe(401);
  });
});

// ── GET /api/shops/:id/follow-status ─────────────────────────────────────────

describe('GET /api/shops/:id/follow-status', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 + followed:true khi đang theo dõi', async () => {
    supabaseMock.__setSelectResult({ user_id: 'user-001', shop_id: SHOP_ID });

    const res = await request(app)
      .get(`/api/shops/${SHOP_ID}/follow-status`)
      .set(BUYER_AUTH);

    expect(res.status).toBe(200);
    expect(res.body.followed).toBe(true);
  });

  it('200 + followed:false khi chưa theo dõi', async () => {
    supabaseMock.__setSelectResult(null);

    const res = await request(app)
      .get(`/api/shops/${SHOP_ID}/follow-status`)
      .set(BUYER_AUTH);

    expect(res.status).toBe(200);
    expect(res.body.followed).toBe(false);
  });

  it('401 khi không có token', async () => {
    const res = await request(app).get(`/api/shops/${SHOP_ID}/follow-status`);
    expect(res.status).toBe(401);
  });
});

// ── GET /api/shops/me/following ───────────────────────────────────────────────

describe('GET /api/shops/me/following', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 + { data, count } khi lấy danh sách shop đang follow', async () => {
    supabaseMock.__setSelectResult({
      followed_at: new Date().toISOString(),
      shops: {
        id: SHOP_ID, name: 'Lạc Yên Foods', slug: 'lac-yen-foods',
        logo_url: null, rating: 4.8, total_sales: 500, follower_count: 120,
      },
    });

    const res = await request(app)
      .get('/api/shops/me/following')
      .set(BUYER_AUTH);

    expect(res.status).toBe(200);
    expect(res.body.data).toBeDefined();
    expect(res.body.count).toBeDefined();
  });

  it('401 khi không có token', async () => {
    const res = await request(app).get('/api/shops/me/following');
    expect(res.status).toBe(401);
  });
});
