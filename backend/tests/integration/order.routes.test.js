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

const AUTH       = bearerHeader({ id: 'user-001', role: 'buyer' });
const AUTH_SELLER = bearerHeader({ id: 'seller-001', role: 'seller' });

const SESSION_UUID  = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const PRODUCT_UUID  = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const VARIANT_UUID  = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const CART_ITEM_UUID = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const ORDER_UUID    = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

// ── Fixtures ──────────────────────────────────────────────────────────────────

function makeLiveProduct(overrides = {}) {
  return {
    id:           PRODUCT_UUID,
    session_id:   SESSION_UUID,
    product_name: 'Gạo ST25 1kg',
    sale_price:   85_000,
    stock_left:   50,
    live_sessions: { title: 'Lạc Yên Foods Live', seller_id: 'seller-001' },
    ...overrides,
  };
}

function makeOrder(overrides = {}) {
  return {
    id:             ORDER_UUID,
    buyer_id:       'user-001',
    buyer_name:     'Nguyen A',
    session_id:     SESSION_UUID,
    product_id:     PRODUCT_UUID,
    quantity:       2,
    unit_price:     85_000,
    total_price:    170_000,
    status:         'confirmed',
    payment_status: 'pending',
    payment_method: 'cod',
    created_at:     new Date().toISOString(),
    ...overrides,
  };
}

// ── POST /api/orders (live order) ─────────────────────────────────────────────

describe('POST /api/orders', () => {
  beforeEach(() => supabaseMock.__reset());

  it('201 khi đặt hàng live thành công', async () => {
    supabaseMock.__setSelectQueue(
      makeLiveProduct(),   // findLiveProduct
    );
    supabaseMock.__setInsertResult(makeOrder());

    const res = await request(app)
      .post('/api/orders')
      .set(AUTH)
      .send({
        sessionId:   SESSION_UUID,
        productId:   PRODUCT_UUID,
        quantity:    2,
        buyerName:   'Nguyen A',
      });

    expect(res.status).toBe(201);
    expect(res.body.order).toBeDefined();
    expect(res.body.product).toBeDefined();
    expect(res.body.product.unitPrice).toBe(85_000);
  });

  it('422 khi thiếu sessionId', async () => {
    const res = await request(app)
      .post('/api/orders')
      .set(AUTH)
      .send({ productId: PRODUCT_UUID, quantity: 1, buyerName: 'A' });

    expect(res.status).toBe(422);
  });

  it('422 khi quantity = 0', async () => {
    const res = await request(app)
      .post('/api/orders')
      .set(AUTH)
      .send({ sessionId: SESSION_UUID, productId: PRODUCT_UUID, quantity: 0, buyerName: 'A' });

    expect(res.status).toBe(422);
  });

  it('422 khi quantity > 99', async () => {
    const res = await request(app)
      .post('/api/orders')
      .set(AUTH)
      .send({ sessionId: SESSION_UUID, productId: PRODUCT_UUID, quantity: 100, buyerName: 'A' });

    expect(res.status).toBe(422);
  });

  it('401 khi không có token', async () => {
    const res = await request(app)
      .post('/api/orders')
      .send({ sessionId: SESSION_UUID, productId: PRODUCT_UUID, quantity: 1, buyerName: 'A' });

    expect(res.status).toBe(401);
  });

  it('404 khi product không tồn tại', async () => {
    supabaseMock.__setSelectResult(null); // findLiveProduct → null

    const res = await request(app)
      .post('/api/orders')
      .set(AUTH)
      .send({ sessionId: SESSION_UUID, productId: PRODUCT_UUID, quantity: 1, buyerName: 'A' });

    expect(res.status).toBe(404);
  });

  it('409 khi hết hàng', async () => {
    supabaseMock.__setSelectQueue(makeLiveProduct({ stock_left: 0 }));

    const res = await request(app)
      .post('/api/orders')
      .set(AUTH)
      .send({ sessionId: SESSION_UUID, productId: PRODUCT_UUID, quantity: 1, buyerName: 'A' });

    expect(res.status).toBe(409);
  });
});

// ── POST /api/orders/checkout (cart checkout) ─────────────────────────────────

describe('POST /api/orders/checkout', () => {
  beforeEach(() => supabaseMock.__reset());

  const VALID_BODY = {
    items: [
      { cartItemId: CART_ITEM_UUID, variantId: VARIANT_UUID, quantity: 2, unitPrice: 85_000, productName: 'Gạo ST25' },
    ],
    paymentMethod: 'cod',
  };

  it('201 khi checkout thành công', async () => {
    supabaseMock.__setInsertResult(makeOrder());

    const res = await request(app)
      .post('/api/orders/checkout')
      .set(AUTH)
      .send(VALID_BODY);

    expect(res.status).toBe(201);
    expect(res.body.orders).toBeDefined();
    expect(res.body.summary).toBeDefined();
  });

  it('201 với paymentMethod momo', async () => {
    supabaseMock.__setInsertResult(makeOrder({ payment_method: 'momo' }));

    const res = await request(app)
      .post('/api/orders/checkout')
      .set(AUTH)
      .send({ ...VALID_BODY, paymentMethod: 'momo' });

    expect(res.status).toBe(201);
  });

  it('422 khi items rỗng', async () => {
    const res = await request(app)
      .post('/api/orders/checkout')
      .set(AUTH)
      .send({ items: [], paymentMethod: 'cod' });

    expect(res.status).toBe(422);
  });

  it('422 khi thiếu items', async () => {
    const res = await request(app)
      .post('/api/orders/checkout')
      .set(AUTH)
      .send({ paymentMethod: 'cod' });

    expect(res.status).toBe(422);
  });

  it('422 khi paymentMethod không hợp lệ', async () => {
    const res = await request(app)
      .post('/api/orders/checkout')
      .set(AUTH)
      .send({ ...VALID_BODY, paymentMethod: 'cash' });

    expect(res.status).toBe(422);
  });

  it('422 khi variantId không phải UUID', async () => {
    const res = await request(app)
      .post('/api/orders/checkout')
      .set(AUTH)
      .send({
        items: [{ cartItemId: CART_ITEM_UUID, variantId: 'not-uuid', quantity: 1, unitPrice: 1000, productName: 'A' }],
        paymentMethod: 'cod',
      });

    expect(res.status).toBe(422);
  });

  it('401 khi không có token', async () => {
    const res = await request(app)
      .post('/api/orders/checkout')
      .send(VALID_BODY);

    expect(res.status).toBe(401);
  });

  it('summary.subtotal đúng với nhiều items', async () => {
    supabaseMock.__setInsertResult(makeOrder({ total_price: 208_000 }));

    const res = await request(app)
      .post('/api/orders/checkout')
      .set(AUTH)
      .send({
        items: [
          { cartItemId: CART_ITEM_UUID, variantId: VARIANT_UUID, quantity: 2, unitPrice: 85_000, productName: 'Gạo ST25' },
          { cartItemId: 'dddddddd-dddd-dddd-dddd-dddddddddddb', variantId: 'cccccccc-cccc-cccc-cccc-ccccccccccca', quantity: 1, unitPrice: 38_000, productName: 'Trứng gà' },
        ],
        paymentMethod: 'cod',
      });

    expect(res.status).toBe(201);
    expect(res.body.summary.subtotal).toBe(208_000);
  });
});

// ── GET /api/orders/my/list ───────────────────────────────────────────────────

describe('GET /api/orders/my/list', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 + pagination khi có token', async () => {
    supabaseMock.__setSelectResult(makeOrder());

    const res = await request(app)
      .get('/api/orders/my/list')
      .set(AUTH);

    expect(res.status).toBe(200);
    expect(res.body.data).toBeDefined();
    expect(res.body.pagination).toMatchObject({
      page:  expect.any(Number),
      limit: expect.any(Number),
      total: expect.any(Number),
    });
  });

  it('200 với query params page/limit', async () => {
    supabaseMock.__setSelectResult(makeOrder());

    const res = await request(app)
      .get('/api/orders/my/list?page=2&limit=5')
      .set(AUTH);

    expect(res.status).toBe(200);
    expect(res.body.pagination.page).toBe(2);
    expect(res.body.pagination.limit).toBe(5);
  });

  it('401 khi không có token', async () => {
    const res = await request(app).get('/api/orders/my/list');
    expect(res.status).toBe(401);
  });
});

// ── GET /api/orders/:sessionId ────────────────────────────────────────────────

describe('GET /api/orders/:sessionId', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 khi seller xem đúng session của mình', async () => {
    supabaseMock.__setSelectQueue(
      { id: SESSION_UUID, seller_id: 'seller-001' },  // findSessionOwner
      makeOrder(),                                     // findOrdersBySession
    );

    const res = await request(app)
      .get(`/api/orders/${SESSION_UUID}`)
      .set(AUTH_SELLER);

    expect(res.status).toBe(200);
  });

  it('404 khi session không tồn tại', async () => {
    supabaseMock.__setSelectResult(null);

    const res = await request(app)
      .get(`/api/orders/${SESSION_UUID}`)
      .set(AUTH_SELLER);

    expect(res.status).toBe(404);
  });

  it('404 khi buyer cố xem session của người khác (BOLA)', async () => {
    supabaseMock.__setSelectResult({ id: SESSION_UUID, seller_id: 'other-seller' });

    const res = await request(app)
      .get(`/api/orders/${SESSION_UUID}`)
      .set(AUTH);  // buyer, không phải seller

    expect(res.status).toBe(404);
  });

  it('401 khi không có token', async () => {
    const res = await request(app).get(`/api/orders/${SESSION_UUID}`);
    expect(res.status).toBe(401);
  });
});
