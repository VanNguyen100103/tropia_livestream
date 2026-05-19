'use strict';

const { ValidationError, NotFoundError, ConflictError } = require('../errors/AppError');
const repo = require('../repositories/coupon.repository');

/**
 * Validate coupon và tính discount.
 * @returns {{ coupon, discountAmount, finalPrice }}
 */
async function applyCoupon(code, userId, orderTotal) {
  const coupon = await repo.findByCode(code);
  if (!coupon) throw new ValidationError('Mã giảm giá không hợp lệ hoặc đã hết hạn');

  if (coupon.max_uses !== null && coupon.used_count >= coupon.max_uses) {
    throw new ValidationError('Mã giảm giá đã được dùng hết');
  }

  if (orderTotal < (coupon.min_order_value || 0)) {
    throw new ValidationError(
      `Đơn hàng tối thiểu ${coupon.min_order_value.toLocaleString('vi-VN')} đ để dùng mã này`
    );
  }

  if (await repo.hasUsed(coupon.id, userId)) {
    throw new ValidationError('Bạn đã dùng mã giảm giá này rồi');
  }

  let discountAmount =
    coupon.discount_type === 'percent'
      ? (orderTotal * coupon.discount_value) / 100
      : coupon.discount_value;

  // Giới hạn tối đa nếu có
  if (coupon.max_discount && discountAmount > coupon.max_discount) {
    discountAmount = coupon.max_discount;
  }

  discountAmount = Math.min(discountAmount, orderTotal); // không giảm quá tổng tiền

  return {
    coupon,
    discountAmount: Math.round(discountAmount),
    finalPrice:     Math.round(orderTotal - discountAmount),
  };
}

async function listCoupons(query) {
  const page          = Math.max(1, parseInt(query.page  || '1',  10));
  const limit         = Math.min(100, Math.max(1, parseInt(query.limit || '20', 10)));
  const offset        = (page - 1) * limit;
  const includeExpired = query.all === 'true';
  const { data, count } = await repo.listAll({ offset, limit, includeExpired });
  return { data, pagination: { page, limit, total: count, totalPages: Math.ceil(count / limit) } };
}

async function validateCoupon(code, userId, orderTotal) {
  return applyCoupon(code, userId, orderTotal);
}

async function createCoupon(body, adminId) {
  if (await repo.codeExists(body.code)) throw new ConflictError('Mã coupon đã tồn tại');
  return repo.createCoupon(body, adminId);
}

async function updateCoupon(id, body) {
  if (body.code && await repo.codeExists(body.code, id)) {
    throw new ConflictError('Mã coupon đã tồn tại');
  }
  const data = await repo.updateCoupon(id, body);
  if (!data) throw new NotFoundError('Coupon not found');
  return data;
}

async function deactivateCoupon(id) {
  const coupon = await repo.findById(id);
  if (!coupon) throw new NotFoundError('Coupon not found');
  await repo.deactivateCoupon(id);
}

async function getAvailableCoupons() {
  return repo.listPlatformCoupons();
}

async function getShopCoupons(shopId) {
  return repo.listShopCoupons(shopId);
}

module.exports = { applyCoupon, listCoupons, validateCoupon, createCoupon, updateCoupon, deactivateCoupon, getAvailableCoupons, getShopCoupons };
