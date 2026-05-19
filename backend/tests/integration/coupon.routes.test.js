'use strict';

jest.mock('../../src/lib/supabase', () => require('../mocks/supabase.mock'));
jest.mock('../../src/lib/redis',    () => require('../mocks/redis.mock'));
jest.mock('../../src/lib/rabbitmq', () => ({ publish: jest.fn().mockResolvedValue(undefined), connect: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../src/middleware/security', () => ({
  helmetConfig:     () => (_, __, next) => next(),
  requestId:        () => (_, __, next) => next(),
  sanitizeInput:    () => (_, __, next) => next(),
  requestSizeGuard: () => (_, __, next) => next(),
  auditLog:         () => (_, __, next) => next(),
  logSecurityEvent: jest.fn(),
}));

const request      = require('supertest');
const app          = require('../../src/index');
const { bearerHeader } = require('../helpers/token');
const supabaseMock = require('../mocks/supabase.mock');

const AUTH_BUYER = bearerHeader({ id: 'user-001', role: 'buyer' });
const AUTH_ADMIN = bearerHeader({ id: 'admin-001', role: 'admin' });
const COUPON_UUID = 'ffffffff-ffff-ffff-ffff-ffffffffffff';

function makeCoupon(overrides = {}) {
  return {
    id:              COUPON_UUID,
    code:            'SALE20',
    discount_type:   'percent',
    discount_value:  20,
    min_order_value: 200_000,
    max_discount:    100_000,
    max_uses:        500,
    used_count:      10,
    expires_at:      new Date(Date.now() + 86400_000 * 30).toISOString(),
    is_active:       true,
    created_at:      new Date().toISOString(),
    ...overrides,
  };
}

// ── POST /api/coupons/validate ────────────────────────────────────────────────

describe('POST /api/coupons/validate', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 khi coupon hợp lệ', async () => {
    supabaseMock.__setSelectQueue(
      makeCoupon(),   // findByCode
      null,           // hasUsed → false (null = chưa dùng)
    );

    const res = await request(app)
      .post('/api/coupons/validate')
      .set(AUTH_BUYER)
      .send({ code: 'SALE20', orderTotal: 300_000 });

    expect(res.status).toBe(200);
    expect(res.body.discountAmount).toBeGreaterThan(0);
    expect(res.body.finalPrice).toBeLessThan(300_000);
    expect(res.body.code).toBe('SALE20');
  });

  it('422 khi thiếu code', async () => {
    const res = await request(app)
      .post('/api/coupons/validate')
      .set(AUTH_BUYER)
      .send({ orderTotal: 100_000 });

    expect(res.status).toBe(422);
  });

  it('422 khi thiếu orderTotal', async () => {
    const res = await request(app)
      .post('/api/coupons/validate')
      .set(AUTH_BUYER)
      .send({ code: 'SALE20' });

    expect(res.status).toBe(422);
  });

  it('422 khi orderTotal âm', async () => {
    const res = await request(app)
      .post('/api/coupons/validate')
      .set(AUTH_BUYER)
      .send({ code: 'SALE20', orderTotal: -100 });

    expect(res.status).toBe(422);
  });

  it('400 khi coupon không tồn tại', async () => {
    supabaseMock.__setSelectResult(null); // findByCode → null

    const res = await request(app)
      .post('/api/coupons/validate')
      .set(AUTH_BUYER)
      .send({ code: 'NOTEXIST', orderTotal: 300_000 });

    expect(res.status).toBe(422);
  });

  it('422 khi đơn hàng chưa đạt min_order_value', async () => {
    supabaseMock.__setSelectQueue(
      makeCoupon({ min_order_value: 500_000 }),
      null,
    );

    const res = await request(app)
      .post('/api/coupons/validate')
      .set(AUTH_BUYER)
      .send({ code: 'SALE20', orderTotal: 100_000 });

    expect(res.status).toBe(422);
  });

  it('422 khi người dùng đã dùng coupon này rồi', async () => {
    supabaseMock.__setSelectQueue(
      makeCoupon(),
      { id: 'usage-id' },  // hasUsed → đã có usage
    );

    const res = await request(app)
      .post('/api/coupons/validate')
      .set(AUTH_BUYER)
      .send({ code: 'SALE20', orderTotal: 300_000 });

    expect(res.status).toBe(422);
  });

  it('401 khi không có token', async () => {
    const res = await request(app)
      .post('/api/coupons/validate')
      .send({ code: 'SALE20', orderTotal: 300_000 });

    expect(res.status).toBe(401);
  });
});

// ── GET /api/coupons/available ────────────────────────────────────────────────

describe('GET /api/coupons/available', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 + data array khi có token', async () => {
    supabaseMock.__setSelectResult(makeCoupon());

    const res = await request(app)
      .get('/api/coupons/available')
      .set(AUTH_BUYER);

    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.data)).toBe(true);
  });

  it('401 khi không có token', async () => {
    const res = await request(app).get('/api/coupons/available');
    expect(res.status).toBe(401);
  });
});

// ── GET /api/coupons (admin) ──────────────────────────────────────────────────

describe('GET /api/coupons', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 + pagination khi là admin', async () => {
    supabaseMock.__setSelectResult(makeCoupon());

    const res = await request(app)
      .get('/api/coupons')
      .set(AUTH_ADMIN);

    expect(res.status).toBe(200);
    expect(res.body.data).toBeDefined();
    expect(res.body.pagination).toBeDefined();
  });

  it('403 khi buyer cố truy cập', async () => {
    const res = await request(app)
      .get('/api/coupons')
      .set(AUTH_BUYER);

    expect(res.status).toBe(403);
  });

  it('401 khi không có token', async () => {
    const res = await request(app).get('/api/coupons');
    expect(res.status).toBe(401);
  });
});

// ── POST /api/coupons (admin) ─────────────────────────────────────────────────

describe('POST /api/coupons', () => {
  beforeEach(() => supabaseMock.__reset());

  const VALID_BODY = {
    code:           'NEWCODE50',
    discount_type:  'percent',
    discount_value: 50,
    min_order_value: 300_000,
    max_discount:   200_000,
    max_uses:       100,
    expires_at:     new Date(Date.now() + 86400_000 * 30).toISOString(),
    is_active:      true,
  };

  it('201 khi admin tạo coupon mới', async () => {
    supabaseMock.__setSelectResult(null);   // codeExists → false
    supabaseMock.__setInsertResult(makeCoupon({ code: 'NEWCODE50' }));

    const res = await request(app)
      .post('/api/coupons')
      .set(AUTH_ADMIN)
      .send(VALID_BODY);

    expect(res.status).toBe(201);
  });

  it('409 khi mã đã tồn tại', async () => {
    supabaseMock.__setSelectResult(makeCoupon({ code: 'NEWCODE50' })); // codeExists → true

    const res = await request(app)
      .post('/api/coupons')
      .set(AUTH_ADMIN)
      .send(VALID_BODY);

    expect(res.status).toBe(409);
  });

  it('422 khi thiếu expires_at', async () => {
    const { expires_at, ...body } = VALID_BODY;
    const res = await request(app)
      .post('/api/coupons')
      .set(AUTH_ADMIN)
      .send(body);

    expect(res.status).toBe(422);
  });

  it('422 khi code chứa ký tự đặc biệt', async () => {
    const res = await request(app)
      .post('/api/coupons')
      .set(AUTH_ADMIN)
      .send({ ...VALID_BODY, code: 'code with spaces' });

    expect(res.status).toBe(422);
  });

  it('403 khi buyer cố tạo coupon', async () => {
    const res = await request(app)
      .post('/api/coupons')
      .set(AUTH_BUYER)
      .send(VALID_BODY);

    expect(res.status).toBe(403);
  });
});

// ── PATCH /api/coupons/:id (admin) ────────────────────────────────────────────

describe('PATCH /api/coupons/:id', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 khi admin cập nhật coupon', async () => {
    supabaseMock.__setSelectResult(null);   // codeExists → false
    supabaseMock.__setUpdateResult(makeCoupon({ discount_value: 30 }));

    const res = await request(app)
      .patch(`/api/coupons/${COUPON_UUID}`)
      .set(AUTH_ADMIN)
      .send({ discount_value: 30 });

    expect(res.status).toBe(200);
  });

  it('403 khi buyer cố cập nhật', async () => {
    const res = await request(app)
      .patch(`/api/coupons/${COUPON_UUID}`)
      .set(AUTH_BUYER)
      .send({ discount_value: 30 });

    expect(res.status).toBe(403);
  });
});

// ── DELETE /api/coupons/:id (admin – deactivate) ──────────────────────────────

describe('DELETE /api/coupons/:id', () => {
  beforeEach(() => supabaseMock.__reset());

  it('204 khi admin deactivate coupon', async () => {
    supabaseMock.__setSelectResult(makeCoupon());
    supabaseMock.__setUpdateResult(makeCoupon({ is_active: false }));

    const res = await request(app)
      .delete(`/api/coupons/${COUPON_UUID}`)
      .set(AUTH_ADMIN);

    expect(res.status).toBe(204);
  });

  it('404 khi coupon không tồn tại', async () => {
    supabaseMock.__setSelectResult(null);

    const res = await request(app)
      .delete(`/api/coupons/${COUPON_UUID}`)
      .set(AUTH_ADMIN);

    expect(res.status).toBe(404);
  });

  it('403 khi buyer cố deactivate', async () => {
    const res = await request(app)
      .delete(`/api/coupons/${COUPON_UUID}`)
      .set(AUTH_BUYER);

    expect(res.status).toBe(403);
  });

  it('401 khi không có token', async () => {
    const res = await request(app).delete(`/api/coupons/${COUPON_UUID}`);
    expect(res.status).toBe(401);
  });
});
