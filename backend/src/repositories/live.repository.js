'use strict';

const supabase = require('../lib/supabase');

async function _enrichWithShopId(sessions) {
  if (!sessions || sessions.length === 0) return sessions;
  const sellerIds = [...new Set(sessions.map(s => s.seller_id))];
  const { data: shops } = await supabase
    .from('shops')
    .select('id, seller_id')
    .in('seller_id', sellerIds);
  const shopMap = Object.fromEntries((shops || []).map(sh => [sh.seller_id, sh.id]));
  return sessions.map(s => ({ ...s, shop_id: shopMap[s.seller_id] ?? null }));
}

async function findActiveSessions() {
  const { data, error } = await supabase
    .from('live_sessions')
    .select(`*, profiles:seller_id(name,avatar_url,shop_name), live_session_products(*)`)
    .eq('status', 'live')
    .order('started_at', { ascending: false });
  if (error) throw error;
  return _enrichWithShopId(data || []);
}

async function findSessionById(id) {
  const { data, error } = await supabase
    .from('live_sessions')
    .select(`*, profiles:seller_id(name,avatar_url,shop_name), live_session_products(*)`)
    .eq('id', id)
    .single();
  if (error) return null;
  const enriched = await _enrichWithShopId([data]);
  return enriched[0];
}

async function findSessionOwner(id) {
  const { data } = await supabase
    .from('live_sessions').select('seller_id').eq('id', id).single();
  return data;
}

async function createSession(sellerId, title, category, agoraChannel) {
  const { data, error } = await supabase
    .from('live_sessions')
    .insert({ seller_id: sellerId, title, category, agora_channel: agoraChannel })
    .select()
    .single();
  if (error) throw error;
  return data;
}

async function insertSessionProducts(rows) {
  const { error } = await supabase.from('live_session_products').insert(rows);
  if (error) throw error;
}

async function insertSessionCoupons(rows) {
  const { error } = await supabase
    .from('coupons')
    .upsert(rows, { onConflict: 'code', ignoreDuplicates: false });
  if (error) throw error;
}

async function endSession(id) {
  const { data, error } = await supabase
    .from('live_sessions')
    .update({ status: 'ended', ended_at: new Date().toISOString() })
    .eq('id', id)
    .select()
    .single();
  if (error) throw error;
  return data;
}

// Schema: live_viewers(session_id, user_id, joined_at) — PK(session_id, user_id)
// Trigger tự cập nhật viewer_count khi INSERT / DELETE
async function upsertViewer(sessionId, userId) {
  // Insert ignore nếu đã tồn tại (onConflict do nothing)
  await supabase
    .from('live_viewers')
    .upsert(
      { session_id: sessionId, user_id: userId },
      { onConflict: 'session_id,user_id', ignoreDuplicates: true },
    );
}

async function setViewerLeft(sessionId, userId) {
  // Xoá record → trigger tự giảm viewer_count
  await supabase
    .from('live_viewers')
    .delete()
    .match({ session_id: sessionId, user_id: userId });
}

async function incrementLikes(sessionId) {
  await supabase.rpc('increment_likes', { session_id: sessionId });
}

// Schema: chat_messages(id, session_id, user_id, username, avatar_url, message, is_host, created_at)
async function insertChatMessage({ sessionId, userId, userName, userAvatar, type, message, isHost = false }) {
  const row = {
    session_id: sessionId,
    user_id:    userId,
    username:   userName,
    avatar_url: userAvatar,
    message,
  };
  // is_host chỉ insert nếu true (tránh lỗi nếu cột chưa có trong schema cũ)
  if (isHost) row.is_host = true;

  const { data, error } = await supabase
    .from('chat_messages')
    .insert(row)
    .select()
    .single();
  if (error) throw error;
  return data;
}

async function fetchRecentChats(sessionId, limit = 50) {
  const { data, error } = await supabase
    .from('chat_messages')
    .select('id, user_id, username, avatar_url, message, is_host, created_at')
    .eq('session_id', sessionId)
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data || []).reverse();
}

async function fetchSessionStats(sessionId) {
  const { data, error } = await supabase
    .from('live_sessions')
    .select('viewer_count, like_count, order_count, revenue, status, cart_add_count, follow_count')
    .eq('id', sessionId)
    .single();
  if (error) throw error;
  return data || {};
}

async function incrementCartAdd(sessionId) {
  await supabase.rpc('increment_cart_add', { session_id: sessionId });
}

async function incrementFollow(sessionId) {
  await supabase.rpc('increment_follow_count', { session_id: sessionId });
}

// ── Coupons for a live session (filter by session_id) ────────────────────────
async function fetchSessionCoupons(sessionId) {
  const { data, error } = await supabase
    .from('coupons')
    .select('id, code, discount_type, discount_value, min_order_value, max_discount, expires_at')
    .eq('session_id', sessionId)
    .eq('is_active', true)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data || [];
}

module.exports = {
  findActiveSessions,
  findSessionById,
  findSessionOwner,
  createSession,
  insertSessionProducts,
  insertSessionCoupons,
  endSession,
  upsertViewer,
  setViewerLeft,
  incrementLikes,
  incrementCartAdd,
  incrementFollow,
  insertChatMessage,
  fetchRecentChats,
  fetchSessionStats,
  fetchSessionCoupons,
};
