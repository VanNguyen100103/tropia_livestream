'use strict';

const { v4: uuidv4 }        = require('uuid');
const { invalidatePattern } = require('../lib/redis');
const { NotFoundError }     = require('../errors/AppError');
const repo = require('../repositories/live.repository');

async function getActiveSessions() {
  return repo.findActiveSessions();
}

async function getSessionById(id) {
  const data = await repo.findSessionById(id);
  if (!data) throw new NotFoundError('Session not found');
  return data;
}

async function startSession(sellerId, { title, category, products, coupons = [] }) {
  const agoraChannel = `live_${uuidv4().replace(/-/g, '').substring(0, 16)}`;
  const session      = await repo.createSession(sellerId, title, category, agoraChannel);

  if (products.length > 0) {
    const rows = products.map((p, i) => ({
      session_id:     session.id,
      product_name:   p.name,
      image_url:      p.imageUrl || null,
      original_price: p.originalPrice,
      sale_price:     p.salePrice,
      discount_pct:   p.discountPercent,
      stock_left:     p.totalStock,
      sold_count:     0,
      unit:           p.unit,
      category:       p.category || category,
      sort_order:     i,
    }));
    await repo.insertSessionProducts(rows);
  }

  if (coupons.length > 0) {
    const couponRows = coupons.map((c) => ({
      code:            c.code.toUpperCase(),
      discount_type:   c.isPercentage ? 'percent' : 'fixed',
      discount_value:  c.discountValue,
      min_order_value: c.minOrderValue || 0,
      max_uses:        c.maxUses ?? null,
      expires_at:      c.expiresAt ?? new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
      session_id:      session.id,
      created_by:      sellerId,
    }));
    await repo.insertSessionCoupons(couponRows);
  }

  await invalidatePattern('live:sessions:*');
  return { session, agoraChannel };
}

async function endSession(id, userId, role) {
  const owner = await repo.findSessionOwner(id);
  if (!owner) throw new NotFoundError('Session not found');
  if (owner.seller_id !== userId && role !== 'admin') {
    throw new NotFoundError('Session not found');
  }

  const data = await repo.endSession(id);
  await invalidatePattern(`live:session:${id}*`);
  await invalidatePattern('live:sessions:*');
  return data;
}

async function joinSession(sessionId, userId) {
  await repo.upsertViewer(sessionId, userId);
}

async function leaveSession(sessionId, userId) {
  await repo.setViewerLeft(sessionId, userId);
}

async function likeSession(sessionId) {
  await repo.incrementLikes(sessionId);
}

async function sendChatMessage(sessionId, user, { message, type, isHost = false }) {
  return repo.insertChatMessage({
    sessionId,
    userId:     user.id,
    userName:   isHost ? 'Trợ lý AI' : (user.fullName || user.name || 'Viewer'),
    userAvatar: user.avatarUrl || user.avatar_url || null,
    type,
    message,
    isHost,
  });
}

async function getRecentChats(sessionId, limit = 50) {
  return repo.fetchRecentChats(sessionId, limit);
}

async function getSessionStats(sessionId) {
  return repo.fetchSessionStats(sessionId);
}

async function getSessionCoupons(sessionId) {
  return repo.fetchSessionCoupons(sessionId);
}

module.exports = {
  getActiveSessions, getSessionById, startSession, endSession,
  joinSession, leaveSession, likeSession, sendChatMessage,
  getRecentChats, getSessionStats, getSessionCoupons,
};
