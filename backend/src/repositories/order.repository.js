'use strict';

const supabase = require('../lib/supabase');

async function findLiveProduct(productId) {
  const { data, error } = await supabase
    .from('live_session_products')
    .select('sale_price, stock_left, product_name, session_id, live_sessions(title)')
    .eq('id', productId)
    .single();
  if (error) return null;
  return data;
}

// Tìm variant thường (từ giỏ hàng không qua live)
async function findVariantForCart(variantId) {
  const { data, error } = await supabase
    .from('product_variants')
    .select('id, sale_price, price, products(id, name)')
    .eq('id', variantId)
    .eq('is_active', true)
    .single();
  if (error) return null;
  return data;
}

async function createOrder({ sessionId, productId, buyerId, buyerName, buyerAvatar, quantity, unitPrice, totalPrice, discountAmount, couponId, productName }) {
  const row = {
    buyer_id:        buyerId,
    buyer_name:      buyerName,
    quantity,
    unit_price:      unitPrice,
    total_price:     totalPrice,
    discount_amount: discountAmount || 0,
    coupon_id:       couponId || null,
    status:          'confirmed',
    payment_status:  'pending',
    payment_method:  'cod',
  };
  if (sessionId)   row.session_id  = sessionId;
  if (productId)   row.product_id  = productId;
  if (productName) row.product_name = productName;
  if (buyerAvatar) row.buyer_avatar = buyerAvatar;

  const { data, error } = await supabase
    .from('live_orders')
    .insert(row)
    .select('id, session_id, product_id, buyer_id, quantity, unit_price, total_price, status, created_at')
    .single();
  if (error) throw error;
  return data;
}

async function findSessionOwner(sessionId) {
  const { data } = await supabase
    .from('live_sessions')
    .select('seller_id')
    .eq('id', sessionId)
    .single();
  return data;
}

async function findOrdersBySession(sessionId) {
  const { data, error } = await supabase
    .from('live_orders')
    .select(`
      id, quantity, unit_price, total_price, status, created_at,
      buyer_name, buyer_avatar,
      live_session_products(product_name, image_url)
    `)
    .eq('session_id', sessionId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}

async function findOrdersByBuyer(buyerId, offset, limit) {
  const { data, error, count } = await supabase
    .from('live_orders')
    .select(`
      id, quantity, unit_price, total_price, status, created_at,
      live_session_products(product_name, image_url),
      live_sessions(title)
    `, { count: 'exact' })
    .eq('buyer_id', buyerId)
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);
  if (error) throw error;
  return { data, count };
}

async function findOrderById(orderId) {
  const { data, error } = await supabase
    .from('live_orders')
    .select('id, buyer_id, buyer_name, total_price, unit_price, discount_amount, quantity, product_name, status, payment_status, payment_method, transaction_id, paid_at')
    .eq('id', orderId)
    .single();
  if (error) return null;
  return data;
}

async function updateOrderPayment(orderId, { status, paymentStatus, paymentMethod, transactionId, paidAt }) {
  const { error } = await supabase
    .from('live_orders')
    .update({
      status,
      payment_status: paymentStatus,
      payment_method: paymentMethod,
      transaction_id: transactionId,
      paid_at:        paidAt,
    })
    .eq('id', orderId);
  if (error) throw error;
}

module.exports = {
  findLiveProduct,
  findVariantForCart,
  createOrder,
  findSessionOwner,
  findOrdersBySession,
  findOrdersByBuyer,
  findOrderById,
  updateOrderPayment,
};
