'use strict';

// Service xử lý đặt hàng từ giỏ hàng thông thường (không bắt buộc qua live session)

const { publish }    = require('../lib/rabbitmq');
const { ConflictError } = require('../errors/AppError');
const repo   = require('../repositories/order.repository');
const logger = require('../lib/logger');

/**
 * Checkout từ giỏ hàng – tạo 1 order duy nhất gộp toàn bộ items.
 * order.total_price = grandTotal sau coupon → payment gateway charge đúng số tiền.
 */
async function checkoutCart({ items, couponCode, discountAmount: clientDiscount, paymentMethod = 'cod', note, buyerId, buyerName }) {
  let totalCouponDiscount = 0;
  let couponId = null;

  const subtotal = items.reduce((s, i) => s + i.unitPrice * i.quantity, 0);
  const totalQuantity = items.reduce((s, i) => s + i.quantity, 0);

  // Áp coupon nếu có code hợp lệ
  if (couponCode) {
    try {
      const couponSvc = require('./coupon.service');
      const result    = await couponSvc.applyCoupon(couponCode, buyerId, subtotal);
      totalCouponDiscount = result.discountAmount;
      couponId            = result.coupon.id;
    } catch (err) {
      logger.warn({ err, couponCode }, 'Cart checkout: coupon apply failed, skipping');
    }
  }

  // Nếu backend không verify được coupon nhưng client đã tính discount (shop coupon, v.v.)
  // → dùng giá trị client gửi lên (đã validate là số nguyên >= 0, tối đa bằng subtotal)
  if (totalCouponDiscount === 0 && clientDiscount > 0) {
    totalCouponDiscount = Math.min(clientDiscount, subtotal);
  }

  const grandTotal = Math.max(0, subtotal - totalCouponDiscount);

  // Tên đơn hàng: tên sản phẩm đầu tiên + số lượng còn lại
  const firstProductName = items[0]?.productName || 'Sản phẩm';
  const productName = items.length > 1
    ? `${firstProductName} và ${items.length - 1} sản phẩm khác`
    : firstProductName;

  // Tạo 1 order duy nhất với tổng giá trị sau coupon
  const order = await repo.createOrder({
    sessionId:     null,
    productId:     null,
    buyerId,
    buyerName,
    buyerAvatar:   null,
    quantity:      totalQuantity,
    unitPrice:     subtotal,
    totalPrice:    grandTotal,
    discountAmount: totalCouponDiscount,
    couponId,
    productName,
  });

  // Ghi nhận coupon usage sau khi order tạo thành công
  if (couponId) {
    try {
      const couponRepo = require('../repositories/coupon.repository');
      await couponRepo.recordUsage(couponId, buyerId, order.id);
    } catch (err) {
      logger.warn({ err }, 'recordUsage failed');
    }
  }

  const orderOut = {
    id:              order.id,
    session_id:      order.session_id,
    product_id:      order.product_id,
    product_name:    productName,
    quantity:        order.quantity,
    unit_price:      order.unit_price,
    total_price:     order.total_price,
    discount_amount: totalCouponDiscount,
    status:          order.status,
    created_at:      order.created_at,
  };

  publish('order.created', {
    orderId: order.id, buyerName, productName,
    quantity: totalQuantity, totalPrice: grandTotal,
    discountAmount: totalCouponDiscount, sessionTitle: 'Tropia Store',
  }).catch(err => logger.warn({ err }, 'Publish order.created failed'));

  logger.info({ buyerId, orderId: order.id, grandTotal, couponCode, paymentMethod }, 'Cart checkout completed');

  return {
    orders: [orderOut],
    summary: { subtotal, couponDiscount: totalCouponDiscount, grandTotal, paymentMethod },
  };
}

module.exports = { checkoutCart };
