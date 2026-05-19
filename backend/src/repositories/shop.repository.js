'use strict';

const supabase = require('../lib/supabase');

async function listShops({ offset, limit }) {
  const { data, error, count } = await supabase
    .from('shops')
    .select('id, name, slug, logo_url, banner_url, rating, total_sales, is_active', { count: 'exact' })
    .eq('is_active', true)
    .order('total_sales', { ascending: false })
    .range(offset, offset + limit - 1);
  if (error) throw error;
  return { data, count };
}

const SHOP_SELECT = '*, profiles!shops_seller_id_fkey(name, avatar_url)';

async function findShopBySlug(slug) {
  // Thử tìm theo slug trước
  const { data: bySlug } = await supabase
    .from('shops').select(SHOP_SELECT).eq('slug', slug).maybeSingle();
  if (bySlug) return bySlug;

  const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (uuidRe.test(slug)) {
    // Thử theo shops.id
    const { data: byId } = await supabase
      .from('shops').select(SHOP_SELECT).eq('id', slug).maybeSingle();
    if (byId) return byId;

    // Thử theo seller_id (profile UUID)
    const { data: bySeller } = await supabase
      .from('shops').select(SHOP_SELECT).eq('seller_id', slug).maybeSingle();
    if (bySeller) return bySeller;
  }

  return null;
}

async function findShopBySeller(sellerId) {
  const { data, error } = await supabase
    .from('shops')
    .select('*')
    .eq('seller_id', sellerId)
    .maybeSingle();
  if (error) throw error;
  return data;
}

async function findShopById(shopId) {
  const { data } = await supabase
    .from('shops').select('seller_id').eq('id', shopId).single();
  return data;
}

async function slugExists(slug, excludeId) {
  let query = supabase.from('shops').select('id').eq('slug', slug);
  if (excludeId) query = query.neq('id', excludeId);
  const { data } = await query.maybeSingle();
  return !!data;
}

async function sellerHasShop(sellerId) {
  const { data } = await supabase
    .from('shops').select('id').eq('seller_id', sellerId).maybeSingle();
  return !!data;
}

async function createShop(body, sellerId) {
  const { data, error } = await supabase
    .from('shops')
    .insert({ ...body, seller_id: sellerId })
    .select()
    .single();
  if (error) throw error;
  return data;
}

async function updateShop(shopId, body) {
  const { data, error } = await supabase
    .from('shops').update(body).eq('id', shopId).select().single();
  if (error) throw error;
  return data;
}

// ── Follow ────────────────────────────────────────────────────────────────────

async function followShop(userId, shopId) {
  const { error } = await supabase
    .from('shop_follows')
    .upsert({ user_id: userId, shop_id: shopId }, { onConflict: 'user_id,shop_id' });
  if (error) throw error;
}

async function unfollowShop(userId, shopId) {
  const { error } = await supabase
    .from('shop_follows')
    .delete()
    .eq('user_id', userId)
    .eq('shop_id', shopId);
  if (error) throw error;
}

async function isFollowing(userId, shopId) {
  const { data } = await supabase
    .from('shop_follows')
    .select('user_id')
    .eq('user_id', userId)
    .eq('shop_id', shopId)
    .maybeSingle();
  return !!data;
}

async function getFollowedShops(userId, { offset = 0, limit = 20 } = {}) {
  const { data, error, count } = await supabase
    .from('shop_follows')
    .select('followed_at, shops(id, name, slug, logo_url, rating, total_sales, follower_count)', { count: 'exact' })
    .eq('user_id', userId)
    .order('followed_at', { ascending: false })
    .range(offset, offset + limit - 1);
  if (error) throw error;
  return { data: data.map(r => ({ ...r.shops, followedAt: r.followed_at })), count };
}

module.exports = {
  listShops,
  findShopBySlug,
  findShopBySeller,
  findShopById,
  slugExists,
  sellerHasShop,
  createShop,
  updateShop,
  followShop,
  unfollowShop,
  isFollowing,
  getFollowedShops,
};
