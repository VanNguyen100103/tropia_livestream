'use strict';

jest.mock('../../src/repositories/order.repository');
jest.mock('../../src/repositories/coupon.repository');
jest.mock('../../src/services/coupon.service');
jest.mock('../../src/lib/redis',    () => ({
  acquireLock: jest.fn(),
  getRedis:    jest.fn(),
}));
jest.mock('../../src/lib/rabbitmq', () => ({ publish: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../src/middleware/security', () => ({ logSecurityEvent: jest.fn() }));

const { acquireLock }  = require('../../src/lib/redis');
const repo             = require('../../src/repositories/order.repository');
const couponRepo       = require('../../src/repositories/coupon.repository');
const couponSvc        = require('../../src/services/coupon.service');
const svc              = require('../../src/services/order.service');
const { NotFoundError, ConflictError } = require('../../src/errors/AppError');

// ── Helpers ───────────────────────────────────────────────────────────────────

const releaseMock = jest.fn().mockResolvedValue(undefined);

function setupLock() {
  acquireLock.mockResolvedValue(releaseMock);
  releaseMock.mockClear();
}

function makeProduct(overrides = {}) {
  return {
    id:           'prod-001',
    product_name: 'Gạo ST25 1kg',
    sale_price:   85_000,
    stock_left:   10,
    live_sessions: { title: 'Tropia Fresh Live' },
    ...overrides,
  };
}

function makeOrder(overrides = {}) {
  return {
    id:         'order-001',
    session_id: 'session-001',
    product_id: 'prod-001',
    buyer_id:   'user-001',
    quantity:   1,
    unit_price: 85_000,
    total_price: 85_000,
    discount_amount: 0,
    status:     'pending',
    ...overrides,
  };
}

// ── placeOrder ────────────────────────────────────────────────────────────────

describe('order.service.placeOrder', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    setupLock();
  });

  it('tạo đơn hàng thành công không có coupon', async () => {
    repo.findLiveProduct.mockResolvedValue(makeProduct());
    repo.createOrder.mockResolvedValue(makeOrder());

    const { order } = await svc.placeOrder({
      sessionId: 'session-001', productId: 'prod-001',
      buyerId: 'user-001', buyerName: 'Alice',
      quantity: 1,
    });

    expect(order.id).toBe('order-001');
    expect(releaseMock).toHaveBeenCalled(); // lock luôn được release
  });

  it('release lock dù throw lỗi (finally block)', async () => {
    repo.findLiveProduct.mockResolvedValue(makeProduct({ stock_left: 0 }));

    await expect(svc.placeOrder({
      sessionId: 's', productId: 'p',
      buyerId: 'u', buyerName: 'Alice', quantity: 1,
    })).rejects.toBeInstanceOf(ConflictError);

    expect(releaseMock).toHaveBeenCalled();
  });

  it('throw NotFoundError khi product không tồn tại', async () => {
    repo.findLiveProduct.mockResolvedValue(null);

    await expect(svc.placeOrder({
      sessionId: 's', productId: 'ghost',
      buyerId: 'u', buyerName: 'Alice', quantity: 1,
    })).rejects.toBeInstanceOf(NotFoundError);
  });

  it('throw ConflictError khi không đủ stock', async () => {
    repo.findLiveProduct.mockResolvedValue(makeProduct({ stock_left: 2 }));

    await expect(svc.placeOrder({
      sessionId: 's', productId: 'prod-001',
      buyerId: 'u', buyerName: 'Alice', quantity: 5,
    })).rejects.toBeInstanceOf(ConflictError);
  });

  it('áp dụng coupon và tính đúng finalPrice', async () => {
    repo.findLiveProduct.mockResolvedValue(makeProduct({ sale_price: 100_000 }));
    couponSvc.applyCoupon.mockResolvedValue({
      coupon: { id: 'coupon-001' },
      discountAmount: 20_000,
      finalPrice:     80_000,
    });
    couponRepo.recordUsage.mockResolvedValue(undefined);
    repo.createOrder.mockResolvedValue(
      makeOrder({ total_price: 80_000, discount_amount: 20_000 })
    );

    const { order, discountAmount } = await svc.placeOrder({
      sessionId: 's', productId: 'prod-001',
      buyerId: 'u', buyerName: 'Alice',
      quantity: 1, couponCode: 'SALE20',
    });

    expect(discountAmount).toBe(20_000);
    expect(order.total_price).toBe(80_000);

    // Phải ghi lịch sử sử dụng coupon
    expect(couponRepo.recordUsage).toHaveBeenCalledWith('coupon-001', 'u', 'order-001');
  });

  it('không gọi coupon service khi không có couponCode', async () => {
    repo.findLiveProduct.mockResolvedValue(makeProduct());
    repo.createOrder.mockResolvedValue(makeOrder());

    await svc.placeOrder({
      sessionId: 's', productId: 'prod-001',
      buyerId: 'u', buyerName: 'Alice', quantity: 1,
    });

    expect(couponSvc.applyCoupon).not.toHaveBeenCalled();
  });
});

// ── getSessionOrders ──────────────────────────────────────────────────────────

describe('order.service.getSessionOrders', () => {
  beforeEach(() => jest.clearAllMocks());

  it('throw NotFoundError khi session không tồn tại', async () => {
    repo.findSessionOwner.mockResolvedValue(null);

    await expect(svc.getSessionOrders('ghost-session', 'u', 'buyer'))
      .rejects.toBeInstanceOf(NotFoundError);
  });

  it('seller của session có thể xem orders', async () => {
    repo.findSessionOwner.mockResolvedValue({ seller_id: 'seller-001' });
    repo.findOrdersBySession.mockResolvedValue([makeOrder()]);

    const result = await svc.getSessionOrders('session-001', 'seller-001', 'seller');
    expect(result).toHaveLength(1);
  });

  it('admin có thể xem orders của bất kỳ session nào', async () => {
    repo.findSessionOwner.mockResolvedValue({ seller_id: 'seller-001' });
    repo.findOrdersBySession.mockResolvedValue([makeOrder()]);

    const result = await svc.getSessionOrders('session-001', 'other-admin', 'admin');
    expect(result).toHaveLength(1);
  });

  it('buyer bị từ chối (BOLA protection)', async () => {
    repo.findSessionOwner.mockResolvedValue({ seller_id: 'seller-001' });

    await expect(svc.getSessionOrders('session-001', 'buyer-999', 'buyer'))
      .rejects.toBeInstanceOf(NotFoundError); // trả 404 thay vì 403 để tránh leak
  });
});
