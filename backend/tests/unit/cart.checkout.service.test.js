'use strict';

jest.mock('../../src/repositories/order.repository');
jest.mock('../../src/repositories/coupon.repository');
jest.mock('../../src/services/coupon.service');
jest.mock('../../src/lib/rabbitmq', () => ({ publish: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../src/lib/logger',   () => ({ info: jest.fn(), warn: jest.fn(), error: jest.fn() }));

const orderRepo  = require('../../src/repositories/order.repository');
const couponRepo = require('../../src/repositories/coupon.repository');
const couponSvc  = require('../../src/services/coupon.service');
const { publish } = require('../../src/lib/rabbitmq');
const { checkoutCart } = require('../../src/services/cart.checkout.service');

// ── Fixtures ──────────────────────────────────────────────────────────────────

function makeItems(overrides = []) {
  return overrides.length ? overrides : [
    { cartItemId: 'ci-1', variantId: 'v-1', productName: 'Gạo ST25', quantity: 2, unitPrice: 85_000 },
    { cartItemId: 'ci-2', variantId: 'v-2', productName: 'Trứng gà', quantity: 1, unitPrice: 38_000 },
  ];
}

function makeOrder(overrides = {}) {
  return {
    id: 'order-001', buyer_id: 'user-001', session_id: null, product_id: null,
    quantity: 3, unit_price: 208_000, total_price: 208_000,
    status: 'confirmed', payment_status: 'pending', created_at: new Date().toISOString(),
    ...overrides,
  };
}

const BASE_ARGS = {
  buyerId:   'user-001',
  buyerName: 'Nguyen A',
  items:     makeItems(),
  couponCode:     null,
  discountAmount: 0,
  paymentMethod:  'cod',
  note:           null,
};

// ── Tính subtotal ─────────────────────────────────────────────────────────────

describe('checkoutCart – tính tiền', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    orderRepo.createOrder.mockResolvedValue(makeOrder());
    couponRepo.recordUsage.mockResolvedValue(undefined);
  });

  it('subtotal = tổng (unitPrice * quantity) của từng item', async () => {
    // 2 * 85_000 + 1 * 38_000 = 208_000
    const result = await checkoutCart(BASE_ARGS);
    expect(result.summary.subtotal).toBe(208_000);
  });

  it('grandTotal = subtotal khi không có coupon', async () => {
    const result = await checkoutCart(BASE_ARGS);
    expect(result.summary.grandTotal).toBe(208_000);
    expect(result.summary.couponDiscount).toBe(0);
  });

  it('grandTotal không âm khi discount > subtotal', async () => {
    couponSvc.applyCoupon.mockResolvedValue({
      discountAmount: 999_999, finalPrice: 0, coupon: { id: 'c-1' },
    });
    orderRepo.createOrder.mockResolvedValue(makeOrder({ total_price: 0 }));

    const result = await checkoutCart({ ...BASE_ARGS, couponCode: 'BIG', discountAmount: 999_999 });
    expect(result.summary.grandTotal).toBeGreaterThanOrEqual(0);
  });

  it('tạo đúng 1 order gộp toàn bộ items', async () => {
    await checkoutCart(BASE_ARGS);
    expect(orderRepo.createOrder).toHaveBeenCalledTimes(1);
    const arg = orderRepo.createOrder.mock.calls[0][0];
    expect(arg.quantity).toBe(3);           // 2 + 1
    expect(arg.totalPrice).toBe(208_000);
  });

  it('productName gộp đúng khi nhiều items', async () => {
    await checkoutCart(BASE_ARGS);
    const arg = orderRepo.createOrder.mock.calls[0][0];
    expect(arg.productName).toContain('và 1 sản phẩm khác');
  });

  it('productName là tên sản phẩm khi chỉ có 1 item', async () => {
    const singleItem = makeItems([
      { cartItemId: 'ci-1', variantId: 'v-1', productName: 'Hạt điều', quantity: 1, unitPrice: 50_000 },
    ]);
    await checkoutCart({ ...BASE_ARGS, items: singleItem });
    const arg = orderRepo.createOrder.mock.calls[0][0];
    expect(arg.productName).toBe('Hạt điều');
  });
});

// ── Coupon backend-verified ───────────────────────────────────────────────────

describe('checkoutCart – coupon backend verify', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    orderRepo.createOrder.mockResolvedValue(makeOrder());
    couponRepo.recordUsage.mockResolvedValue(undefined);
  });

  it('áp dụng discount khi coupon hợp lệ', async () => {
    couponSvc.applyCoupon.mockResolvedValue({
      discountAmount: 20_000, finalPrice: 188_000, coupon: { id: 'coupon-001' },
    });

    const result = await checkoutCart({ ...BASE_ARGS, couponCode: 'SALE20' });
    expect(result.summary.couponDiscount).toBe(20_000);
    expect(result.summary.grandTotal).toBe(188_000);
  });

  it('ghi nhận usage khi coupon hợp lệ', async () => {
    couponSvc.applyCoupon.mockResolvedValue({
      discountAmount: 20_000, finalPrice: 188_000, coupon: { id: 'coupon-001' },
    });

    await checkoutCart({ ...BASE_ARGS, couponCode: 'SALE20' });
    expect(couponRepo.recordUsage).toHaveBeenCalledWith('coupon-001', 'user-001', 'order-001');
  });

  it('bỏ qua coupon thất bại và dùng clientDiscount fallback', async () => {
    couponSvc.applyCoupon.mockRejectedValue(new Error('Coupon invalid'));

    const result = await checkoutCart({
      ...BASE_ARGS,
      couponCode:     'BADCODE',
      discountAmount: 15_000,
    });
    expect(result.summary.couponDiscount).toBe(15_000);
    expect(result.summary.grandTotal).toBe(193_000);
  });

  it('không gọi recordUsage khi coupon thất bại', async () => {
    couponSvc.applyCoupon.mockRejectedValue(new Error('fail'));
    await checkoutCart({ ...BASE_ARGS, couponCode: 'X', discountAmount: 0 });
    expect(couponRepo.recordUsage).not.toHaveBeenCalled();
  });

  it('clientDiscount không vượt quá subtotal', async () => {
    couponSvc.applyCoupon.mockRejectedValue(new Error('fail'));

    const result = await checkoutCart({
      ...BASE_ARGS,
      couponCode:     'X',
      discountAmount: 999_999,  // cố tình lớn hơn subtotal 208_000
    });
    expect(result.summary.couponDiscount).toBe(208_000);
    expect(result.summary.grandTotal).toBe(0);
  });
});

// ── Publish event ─────────────────────────────────────────────────────────────

describe('checkoutCart – publish event', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    orderRepo.createOrder.mockResolvedValue(makeOrder());
    couponRepo.recordUsage.mockResolvedValue(undefined);
  });

  it('publish order.created sau khi tạo order', async () => {
    await checkoutCart(BASE_ARGS);
    expect(publish).toHaveBeenCalledWith('order.created', expect.objectContaining({
      orderId:   'order-001',
      buyerName: 'Nguyen A',
    }));
  });

  it('không throw khi publish thất bại (fire-and-forget)', async () => {
    publish.mockRejectedValueOnce(new Error('RabbitMQ down'));
    await expect(checkoutCart(BASE_ARGS)).resolves.toBeDefined();
  });
});

// ── Cấu trúc response ─────────────────────────────────────────────────────────

describe('checkoutCart – response shape', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    orderRepo.createOrder.mockResolvedValue(makeOrder());
    couponRepo.recordUsage.mockResolvedValue(undefined);
  });

  it('trả về orders array với 1 phần tử', async () => {
    const result = await checkoutCart(BASE_ARGS);
    expect(Array.isArray(result.orders)).toBe(true);
    expect(result.orders).toHaveLength(1);
    expect(result.orders[0].id).toBe('order-001');
  });

  it('trả về summary với đủ fields', async () => {
    const result = await checkoutCart(BASE_ARGS);
    expect(result.summary).toMatchObject({
      subtotal:       expect.any(Number),
      couponDiscount: expect.any(Number),
      grandTotal:     expect.any(Number),
      paymentMethod:  'cod',
    });
  });
});
