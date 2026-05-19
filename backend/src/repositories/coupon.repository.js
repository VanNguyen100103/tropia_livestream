'use strict';

const supabase = require('../lib/supabase');

async function findByCode(code) {
  const { data } = await supabase
    .from('coupons')
    .select('*')
    .eq('code', code.toUpperCase().trim())
    .eq('is_active', true)
    .gt('expires_at', new Date().toISOString())
    .maybeSingle();
  return data;
}

async function findById(id) {
  const { data } = await supabase
    .from('coupons')
    .select('*')
    .eq('id', id)
    .single();
  return data;
}

async function listAll({ offset, limit, includeExpired }) {
  let query = supabase
    .from('coupons')
    .select('*', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);

  if (!includeExpired) query = query.eq('is_active', true);

  const { data, error, count } = await query;
  if (error) throw error;
  return { data, count };
}

async function hasUsed(couponId, userId) {
  const { data } = await supabase
    .from('coupon_usages')
    .select('id')
    .eq('coupon_id', couponId)
    .eq('user_id', userId)
    .maybeSingle();
  return !!data;
}

async function recordUsage(couponId, userId, orderId) {
  const { error } = await supabase
    .from('coupon_usages')
    .insert({ coupon_id: couponId, user_id: userId, order_id: orderId });
  if (error) throw error;

  // tăng used_count
  await supabase.rpc('increment_coupon_uses', { cid: couponId });
}

async function createCoupon(body, adminId) {
  const { data, error } = await supabase
    .from('coupons')
    .insert({ ...body, code: body.code.toUpperCase().trim(), created_by: adminId })
    .select()
    .single();
  if (error) throw error;
  return data;
}

async function updateCoupon(id, body) {
  const patch = { ...body };
  if (patch.code) patch.code = patch.code.toUpperCase().trim();
  const { data, error } = await supabase
    .from('coupons')
    .update(patch)
    .eq('id', id)
    .select()
    .single();
  if (error || !data) return null;
  return data;
}

async function deactivateCoupon(id) {
  await supabase.from('coupons').update({ is_active: false }).eq('id', id);
}

async function codeExists(code, excludeId) {
  let query = supabase
    .from('coupons')
    .select('id')
    .eq('code', code.toUpperCase().trim());
  if (excludeId) query = query.neq('id', excludeId);
  const { data } = await query.maybeSingle();
  return !!data;
}

/** Platform-level coupons (session_id IS NULL), active, not expired */
async function listPlatformCoupons() {
  const { data, error } = await supabase
    .from('coupons')
    .select('id, code, discount_type, discount_value, min_order_value, max_discount, expires_at')
    .eq('is_active', true)
    .is('session_id', null)
    .gt('expires_at', new Date().toISOString())
    .order('discount_value', { ascending: false });
  if (error) throw error;
  return data || [];
}

/** Best available coupons for a shop.
 *  shopId có thể là shops.id hoặc profiles.id (seller_id) — thử cả hai.
 */
async function listShopCoupons(shopId) {
  // Query 1 (shop lookup) và query 2 (sessions by shopId-as-sellerId) chạy song song.
  // Nếu shopId thực ra là shops.id, query 2 sẽ trả rỗng → dùng seller_id từ query 1 để retry.
  const [{ data: shop }, { data: sessionsDirect, error: sErr }] = await Promise.all([
    supabase.from('shops').select('seller_id').eq('id', shopId).maybeSingle(),
    supabase.from('live_sessions').select('id').eq('seller_id', shopId),
  ]);
  if (sErr) throw sErr;

  // Nếu shopId là seller_id trực tiếp → sessionsDirect có data, dùng luôn.
  // Nếu shopId là shops.id → sessionsDirect rỗng, cần lookup lại bằng seller_id thật.
  let sessions = sessionsDirect;
  if ((!sessions || sessions.length === 0) && shop?.seller_id) {
    const { data: s2, error: e2 } = await supabase
      .from('live_sessions').select('id').eq('seller_id', shop.seller_id);
    if (e2) throw e2;
    sessions = s2;
  }

  if (!sessions || sessions.length === 0) return [];

  const sessionIds = sessions.map(s => s.id);

  // Step 3: get active coupons linked to those sessions (không filter expires — validate lúc checkout)
  const { data, error } = await supabase
    .from('coupons')
    .select('id, code, discount_type, discount_value, min_order_value, max_discount, expires_at')
    .eq('is_active', true)
    .in('session_id', sessionIds)
    .order('discount_value', { ascending: false });
  if (error) throw error;
  return data || [];
}

/** Coupon của seller hiện tại — dùng cho màn hình setup live */
async function listSellerCoupons(sellerId) {
  const { data, error } = await supabase
    .from('coupons')
    .select('id, code, discount_type, discount_value, min_order_value, max_discount, expires_at, is_active')
    .eq('created_by', sellerId)
    .eq('is_active', true)
    .gt('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data || [];
}

module.exports = {
  findByCode,
  findById,
  listAll,
  hasUsed,
  recordUsage,
  createCoupon,
  updateCoupon,
  deactivateCoupon,
  codeExists,
  listPlatformCoupons,
  listShopCoupons,
  listSellerCoupons,
};
