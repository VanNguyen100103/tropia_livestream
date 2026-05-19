'use strict';

/**
 * Inventory Worker – quản lý tồn kho.
 * Lắng nghe order.created → giảm stock live_session_products.
 * Lắng nghe order.cancelled → hoàn lại stock.
 *
 * Chạy: node src/workers/inventory.worker.js
 * PM2:  pm2 start src/workers/inventory.worker.js --name inventory-worker
 */

require('dotenv').config();

const { connect, subscribe } = require('../lib/rabbitmq');
const supabase = require('../lib/supabase');
const logger   = require('../lib/logger');

async function decreaseStock(productId, quantity) {
  const { data, error } = await supabase
    .from('live_session_products')
    .select('stock_left, sold_count')
    .eq('id', productId)
    .single();

  if (error || !data) {
    logger.warn({ productId }, 'inventory: product not found');
    return;
  }

  await supabase
    .from('live_session_products')
    .update({
      stock_left: Math.max(0, data.stock_left - quantity),
      sold_count: data.sold_count + quantity,
    })
    .eq('id', productId);

  logger.info({ productId, quantity }, 'Stock decreased');
}

async function increaseStock(productId, quantity) {
  const { data, error } = await supabase
    .from('live_session_products')
    .select('stock_left, sold_count')
    .eq('id', productId)
    .single();

  if (error || !data) return;

  await supabase
    .from('live_session_products')
    .update({
      stock_left: data.stock_left + quantity,
      sold_count: Math.max(0, data.sold_count - quantity),
    })
    .eq('id', productId);

  logger.info({ productId, quantity }, 'Stock restored');
}

async function start() {
  await connect();

  // order.created → giảm stock
  await subscribe('order.created', 'inventory.order.created', async ({ productId, quantity }) => {
    if (!productId || !quantity) return;
    await decreaseStock(productId, quantity);
  });

  // order.cancelled → hoàn lại stock
  await subscribe('order.cancelled', 'inventory.order.cancelled', async ({ productId, quantity }) => {
    if (!productId || !quantity) return;
    await increaseStock(productId, quantity);
  });

  logger.info('Inventory worker ready');
}

start().catch(err => {
  logger.error({ err }, 'Inventory worker crashed');
  process.exit(1);
});
