'use strict';

jest.mock('../../src/repositories/coupon.repository');

const repo = require('../../src/repositories/coupon.repository');
const svc  = require('../../src/services/coupon.service');
const { ValidationError, ConflictError, NotFoundError } = require('../../src/errors/AppError');

// ── Fixtures ─────────────────────────────────────────────────────────────────

function makeCoupon(overrides = {}) {
  return {
    id:             'coupon-001',
    code:           'SALE20',
    discount_type:  'percent',
    discount_value: 20,
    min_order_value: 0,
    max_discount:   null,
    max_uses:       null,
    used_count:     0,
    expires_at:     new Date(Date.now() + 86_400_000).toISOString(),
    is_active:      true,
    ...overrides,
  };
}

const USER_ID    = 'user-001';
const ORDER_TOTAL = 100_000;

// ── applyCoupon ───────────────────────────────────────────────────────────────

describe('coupon.service.applyCoupon', () => {
  beforeEach(() => jest.clearAllMocks());

  it('tính đúng percent discount', async () => {
    repo.findByCode.mockResolvedValue(makeCoupon({ discount_value: 20 }));
    repo.hasUsed.mockResolvedValue(false);

    const { discountAmount, finalPrice } = await svc.applyCoupon('SALE20', USER_ID, 100_000);

    expect(discountAmount).toBe(20_000);
    expect(finalPrice).toBe(80_000);
  });

  it('tính đúng fixed discount', async () => {
    repo.findByCode.mockResolvedValue(makeCoupon({ discount_type: 'fixed', discount_value: 15_000 }));
    repo.hasUsed.mockResolvedValue(false);

    const { discountAmount, finalPrice } = await svc.applyCoupon('FIXED15', USER_ID, 100_000);

    expect(discountAmount).toBe(15_000);
    expect(finalPrice).toBe(85_000);
  });

  it('không giảm quá max_discount', async () => {
    repo.findByCode.mockResolvedValue(
      makeCoupon({ discount_value: 50, max_discount: 30_000 })
    );
    repo.hasUsed.mockResolvedValue(false);

    const { discountAmount } = await svc.applyCoupon('BIG50', USER_ID, 200_000);

    expect(discountAmount).toBe(30_000); // cap tại max_discount
  });

  it('không giảm quá tổng tiền đơn hàng', async () => {
    repo.findByCode.mockResolvedValue(
      makeCoupon({ discount_type: 'fixed', discount_value: 200_000 })
    );
    repo.hasUsed.mockResolvedValue(false);

    const { discountAmount, finalPrice } = await svc.applyCoupon('BIGFIXED', USER_ID, 50_000);

    expect(discountAmount).toBe(50_000);
    expect(finalPrice).toBe(0);
  });

  it('throw ValidationError khi mã không hợp lệ', async () => {
    repo.findByCode.mockResolvedValue(null);

    await expect(svc.applyCoupon('BADCODE', USER_ID, ORDER_TOTAL))
      .rejects.toBeInstanceOf(ValidationError);
  });

  it('throw ValidationError khi đã dùng hết lượt', async () => {
    repo.findByCode.mockResolvedValue(
      makeCoupon({ max_uses: 100, used_count: 100 })
    );

    await expect(svc.applyCoupon('SALE20', USER_ID, ORDER_TOTAL))
      .rejects.toBeInstanceOf(ValidationError);
  });

  it('throw ValidationError khi đơn hàng chưa đạt tối thiểu', async () => {
    repo.findByCode.mockResolvedValue(
      makeCoupon({ min_order_value: 500_000 })
    );

    await expect(svc.applyCoupon('SALE20', USER_ID, 100_000))
      .rejects.toBeInstanceOf(ValidationError);
  });

  it('throw ValidationError khi user đã dùng mã này rồi', async () => {
    repo.findByCode.mockResolvedValue(makeCoupon());
    repo.hasUsed.mockResolvedValue(true);

    await expect(svc.applyCoupon('SALE20', USER_ID, ORDER_TOTAL))
      .rejects.toBeInstanceOf(ValidationError);
  });

  it('làm tròn discountAmount thành số nguyên', async () => {
    repo.findByCode.mockResolvedValue(makeCoupon({ discount_value: 33 }));
    repo.hasUsed.mockResolvedValue(false);

    const { discountAmount } = await svc.applyCoupon('SALE33', USER_ID, 10_000);

    expect(Number.isInteger(discountAmount)).toBe(true);
  });
});

// ── createCoupon ──────────────────────────────────────────────────────────────

describe('coupon.service.createCoupon', () => {
  beforeEach(() => jest.clearAllMocks());

  it('tạo coupon mới thành công', async () => {
    repo.codeExists.mockResolvedValue(false);
    repo.createCoupon.mockResolvedValue(makeCoupon());

    const result = await svc.createCoupon({ code: 'NEW10' }, 'admin-001');

    expect(result.id).toBe('coupon-001');
  });

  it('throw ConflictError khi code đã tồn tại', async () => {
    repo.codeExists.mockResolvedValue(true);

    await expect(svc.createCoupon({ code: 'SALE20' }, 'admin-001'))
      .rejects.toBeInstanceOf(ConflictError);
  });
});

// ── deactivateCoupon ──────────────────────────────────────────────────────────

describe('coupon.service.deactivateCoupon', () => {
  it('throw NotFoundError khi không tìm thấy', async () => {
    repo.findById.mockResolvedValue(null);

    await expect(svc.deactivateCoupon('ghost-id'))
      .rejects.toBeInstanceOf(NotFoundError);
  });

  it('deactivate thành công', async () => {
    repo.findById.mockResolvedValue(makeCoupon());
    repo.deactivateCoupon.mockResolvedValue(undefined);

    await expect(svc.deactivateCoupon('coupon-001')).resolves.toBeUndefined();
    expect(repo.deactivateCoupon).toHaveBeenCalledWith('coupon-001');
  });
});
