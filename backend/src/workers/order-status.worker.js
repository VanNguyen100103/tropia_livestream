'use strict';

/**
 * Order-Status Worker – cập nhật trạng thái đơn hàng theo luồng nghiệp vụ.
 *
 * Events lắng nghe:
 *   payment.success  → confirmed + ghi transaction_id
 *   payment.failed   → cancelled  (nếu chưa paid)
 *   order.cancelled  → cancelled  (do seller hoặc admin)
 *
 * Chạy: node src/workers/order-status.worker.js
 * PM2:  pm2 start src/workers/order-status.worker.js --name order-status-worker
 */

require('dotenv').config();

const { connect, subscribe, publish } = require('../lib/rabbitmq');
const supabase = require('../lib/supabase');
const logger   = require('../lib/logger');

async function getOrder(orderId) {
  const { data } = await supabase
    .from('live_orders')
    .select('id, buyer_id, product_id, quantity, status, payment_status')
    .eq('id', orderId)
    .single();
  return data;
}

async function updateOrder(orderId, patch) {
  const { error } = await supabase
    .from('live_orders')
    .update(patch)
    .eq('id', orderId);
  if (error) throw error;
}

async function start() {
  await connect();

  // payment.success → đơn hàng confirmed + đã thanh toán
  await subscribe('payment.success', 'order-status.payment.success', async ({ orderId, method, transId, amount }) => {
    const order = await getOrder(orderId);
    if (!order) { logger.warn({ orderId }, 'order-status: order not found'); return; }
    if (order.payment_status === 'paid') return; // idempotent

    await updateOrder(orderId, {
      status:         'confirmed',
      payment_status: 'paid',
      payment_method: method,
      transaction_id: transId,
      paid_at:        new Date().toISOString(),
    });

    logger.info({ orderId, method }, 'Order marked paid');
  });

  // payment.failed → huỷ đơn, hoàn stock
  await subscribe('payment.failed', 'order-status.payment.failed', async ({ orderId, reason }) => {
    const order = await getOrder(orderId);
    if (!order) return;
    if (order.status === 'cancelled') return;

    await updateOrder(orderId, {
      status:         'cancelled',
      payment_status: 'failed',
    });

    // Hoàn lại stock
    publish('order.cancelled', {
      orderId,
      buyerId:   order.buyer_id,
      productId: order.product_id,
      quantity:  order.quantity,
      reason:    reason || 'Thanh toán thất bại',
    }).catch(err => logger.warn({ err }, 'Publish order.cancelled failed'));

    logger.info({ orderId }, 'Order cancelled due to payment failure');
  });

  // order.shipped → trạng thái đang giao
  await subscribe('order.shipped', 'order-status.order.shipped', async ({ orderId, trackingCode }) => {
    const order = await getOrder(orderId);
    if (!order || order.status !== 'confirmed') return;

    await updateOrder(orderId, {
      status:        'shipping',
      tracking_code: trackingCode || null,
      shipped_at:    new Date().toISOString(),
    });

    logger.info({ orderId, trackingCode }, 'Order marked shipping');
  });

  // order.delivered → hoàn thành
  await subscribe('order.delivered', 'order-status.order.delivered', async ({ orderId }) => {
    const order = await getOrder(orderId);
    if (!order || order.status !== 'shipping') return;

    await updateOrder(orderId, {
      status:       'delivered',
      delivered_at: new Date().toISOString(),
    });

    logger.info({ orderId }, 'Order marked delivered');
  });

  logger.info('Order-status worker ready');
}

start().catch(err => {
  logger.error({ err }, 'Order-status worker crashed');
  process.exit(1);
});
