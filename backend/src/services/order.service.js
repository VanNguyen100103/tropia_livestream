'use strict';

const { acquireLock }      = require('../lib/redis');
const { publish }          = require('../lib/rabbitmq');
const { logSecurityEvent } = require('../middleware/security');
const { NotFoundError, ConflictError, ForbiddenError } = require('../errors/AppError');
const repo   = require('../repositories/order.repository');
const logger = require('../lib/logger');

async function placeOrder({ sessionId, productId, buyerId, buyerName, buyerAvatar, quantity, couponCode }) {
  const release = await acquireLock(`product:${productId}:stock`, { ttlMs: 5_000, retries: 5 });
  try {
    const product = await repo.findLiveProduct(productId);
    if (!product) throw new NotFoundError('Product not found');
    if (product.stock_left < quantity) throw new ConflictError('Không đủ hàng trong kho');

    const unitPrice = product.sale_price;
    let   totalPrice = unitPrice * quantity;
    let   discountAmount = 0;
    let   couponId = null;

    // Áp dụng coupon nếu có
    if (couponCode) {
      const couponSvc = require('./coupon.service');
      const result    = await couponSvc.applyCoupon(couponCode, buyerId, totalPrice);
      discountAmount  = result.discountAmount;
      totalPrice      = result.finalPrice;
      couponId        = result.coupon.id;
    }

    const order = await repo.createOrder({
      sessionId, productId, buyerId, buyerName, buyerAvatar,
      quantity, unitPrice, totalPrice, discountAmount, couponId,
    });

    // Ghi nhận coupon đã dùng
    if (couponId) {
      const couponRepo = require('../repositories/coupon.repository');
      await couponRepo.recordUsage(couponId, buyerId, order.id);
    }

    logger.info({ orderId: order.id, buyerId, productId, totalPrice, discountAmount }, 'Order created');

    publish('order.created', {
      orderId:      order.id,
      buyerName,
      productName:  product.product_name,
      quantity,
      totalPrice,
      discountAmount,
      sessionTitle: product.live_sessions?.title || 'Tropia Live',
    }).catch(err => logger.warn({ err }, 'Publish order.created failed'));

    return { order, product, discountAmount };
  } finally {
    await release();
  }
}

async function getSessionOrders(sessionId, userId, userRole) {
  const session = await repo.findSessionOwner(sessionId);
  if (!session) throw new NotFoundError('Session not found');

  if (session.seller_id !== userId && userRole !== 'admin') {
    logSecurityEvent('bola.orders_access_denied', { userId, sessionId });
    throw new NotFoundError('Session not found');
  }

  return repo.findOrdersBySession(sessionId);
}

async function getMyOrders(buyerId, page, limit) {
  const offset = (page - 1) * limit;
  const { data, count } = await repo.findOrdersByBuyer(buyerId, offset, limit);
  return { data, pagination: { page, limit, total: count, totalPages: Math.ceil(count / limit) } };
}

module.exports = { placeOrder, getSessionOrders, getMyOrders };
