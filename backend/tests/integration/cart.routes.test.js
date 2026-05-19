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

const AUTH = bearerHeader({ id: 'user-001', role: 'buyer' });

// ── Fixtures ─────────────────────────────────────────────────────────────────

function makeCartItem(overrides = {}) {
  return {
    id:             ITEM_UUID,
    user_id:        'user-001',
    variant_id:     VARIANT_UUID,
    product_id:     'prod-001',
    product_name:   'Gạo ST25 1kg',
    shop_id:        'shop-001',
    shop_name:      'Lạc Yên Foods',
    image_url:      'https://cdn.tropia.vn/rice.jpg',
    attributes:     [{ typeName: 'Khối lượng', value: '1kg', colorHex: null }],
    unit_price:     85_000,
    original_price: 100_000,
    quantity:       2,
    is_selected:    true,
    added_at:       new Date().toISOString(),
    ...overrides,
  };
}

// UUID hợp lệ để pass zod validation
const VARIANT_UUID = '11111111-1111-1111-1111-111111111111';
const ITEM_UUID    = '22222222-2222-2222-2222-222222222222';

function makeVariant() {
  return {
    id:         VARIANT_UUID,
    price:      100_000,
    sale_price: 85_000,
    images:     ['https://cdn.tropia.vn/rice.jpg'],
    is_active:  true,
    products: {
      id:     'prod-001',
      name:   'Gạo ST25 1kg',
      images: ['https://cdn.tropia.vn/rice.jpg'],
      shops:  { id: 'shop-001', name: 'Lạc Yên Foods' },
    },
  };
}

// ── GET /api/cart ─────────────────────────────────────────────────────────────

describe('GET /api/cart', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 + items + summary khi có token', async () => {
    // getCart trả về list items
    supabaseMock.__setSelectResult(makeCartItem());

    const res = await request(app)
      .get('/api/cart')
      .set(AUTH);

    expect(res.status).toBe(200);
    expect(res.body.items).toBeDefined();
    expect(res.body.summary).toBeDefined();
    expect(res.body.summary).toMatchObject({
      totalItems:  expect.any(Number),
      totalPrice:  expect.any(Number),
      totalSaving: expect.any(Number),
    });
  });

  it('401 khi không có token', async () => {
    const res = await request(app).get('/api/cart');
    expect(res.status).toBe(401);
  });
});

// ── POST /api/cart/items ──────────────────────────────────────────────────────

describe('POST /api/cart/items', () => {
  beforeEach(() => supabaseMock.__reset());

  it('201 khi thêm variant hợp lệ', async () => {
    // 1. variant lookup (single) 2. variant_detail (maybeSingle) 3. existing check (maybeSingle→null) 4. insert
    supabaseMock.__setSelectQueue(
      makeVariant(),
      { attributes: [{ typeName: 'Khối lượng', value: '1kg' }] },
      null,
    );
    supabaseMock.__setInsertResult(makeCartItem());

    const res = await request(app)
      .post('/api/cart/items')
      .set(AUTH)
      .send({ variantId: VARIANT_UUID, quantity: 2 });

    expect(res.status).toBe(201);
    expect(res.body.variant_id).toBe(VARIANT_UUID);
  });

  it('422 khi thiếu variantId', async () => {
    const res = await request(app)
      .post('/api/cart/items')
      .set(AUTH)
      .send({ quantity: 1 });

    expect(res.status).toBe(422);
  });

  it('422 khi quantity = 0', async () => {
    const res = await request(app)
      .post('/api/cart/items')
      .set(AUTH)
      .send({ variantId: 'variant-001', quantity: 0 });

    expect(res.status).toBe(422);
  });

  it('422 khi variantId không phải UUID', async () => {
    const res = await request(app)
      .post('/api/cart/items')
      .set(AUTH)
      .send({ variantId: 'not-a-uuid', quantity: 1 });

    expect(res.status).toBe(422);
  });

  it('401 khi không có token', async () => {
    const res = await request(app)
      .post('/api/cart/items')
      .send({ variantId: VARIANT_UUID, quantity: 1 });

    expect(res.status).toBe(401);
  });

  it('404 khi variant không tồn tại hoặc inactive', async () => {
    supabaseMock.__setSelectResult(null); // single() → null

    const res = await request(app)
      .post('/api/cart/items')
      .set(AUTH)
      .send({ variantId: '00000000-0000-0000-0000-000000000000', quantity: 1 });

    expect(res.status).toBe(404);
  });
});

// ── PATCH /api/cart/items/:id/qty ─────────────────────────────────────────────

describe('PATCH /api/cart/items/:id/qty', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 khi cập nhật quantity hợp lệ', async () => {
    supabaseMock.__setUpdateResult(makeCartItem({ quantity: 5 }));

    const res = await request(app)
      .patch(`/api/cart/items/${ITEM_UUID}/qty`)
      .set(AUTH)
      .send({ quantity: 5 });

    expect(res.status).toBe(200);
    expect(res.body.quantity).toBe(5);
  });

  it('422 khi quantity < 1', async () => {
    const res = await request(app)
      .patch(`/api/cart/items/${ITEM_UUID}/qty`)
      .set(AUTH)
      .send({ quantity: 0 });

    expect(res.status).toBe(422);
  });

  it('422 khi quantity > 999', async () => {
    const res = await request(app)
      .patch(`/api/cart/items/${ITEM_UUID}/qty`)
      .set(AUTH)
      .send({ quantity: 1000 });

    expect(res.status).toBe(422);
  });
});

// ── PATCH /api/cart/items/:id/select ─────────────────────────────────────────

describe('PATCH /api/cart/items/:id/select', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 khi cập nhật is_selected', async () => {
    supabaseMock.__setUpdateResult(makeCartItem({ is_selected: false }));

    const res = await request(app)
      .patch(`/api/cart/items/${ITEM_UUID}/select`)
      .set(AUTH)
      .send({ is_selected: false });

    expect(res.status).toBe(200);
    expect(res.body.is_selected).toBe(false);
  });

  it('422 khi is_selected không phải boolean', async () => {
    const res = await request(app)
      .patch(`/api/cart/items/${ITEM_UUID}/select`)
      .set(AUTH)
      .send({ is_selected: 'yes' });

    expect(res.status).toBe(422);
  });
});

// ── DELETE /api/cart/items/:id ────────────────────────────────────────────────

describe('DELETE /api/cart/items/:id', () => {
  beforeEach(() => supabaseMock.__reset());

  it('200 khi xoá item', async () => {
    supabaseMock.__setDeleteResult(null);

    const res = await request(app)
      .delete(`/api/cart/items/${ITEM_UUID}`)
      .set(AUTH);

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it('401 khi không có token', async () => {
    const res = await request(app).delete(`/api/cart/items/${ITEM_UUID}`);
    expect(res.status).toBe(401);
  });
});
