'use strict';

const { z }  = require('zod');
const svc    = require('../services/live.service');
const deepseek = require('../services/deepseek.service');
const repo   = require('../repositories/live.repository');
const { cacheAside } = require('../lib/redis');

const startSchema = z.object({
  title:    z.string().min(2).max(200),
  category: z.string().min(1).max(50),
  products: z.array(z.object({
    name:            z.string().min(1).max(200),
    imageUrl:        z.string().url().optional(),
    originalPrice:   z.number().positive(),
    salePrice:       z.number().positive(),
    discountPercent: z.number().min(0).max(100).default(0),
    totalStock:      z.number().int().min(0),
    unit:            z.string().max(20).default('cái'),
    category:        z.string().max(50).optional(),
  })).max(20).default([]),
  coupons: z.array(z.object({
    code:           z.string().min(3).max(30),
    discountValue:  z.number().positive(),
    isPercentage:   z.boolean(),
    minOrderValue:  z.number().min(0).default(0),
    maxUses:        z.number().int().positive().optional().nullable(),
    expiresAt:      z.string().datetime({ offset: true }).optional().nullable(),
  })).max(5).default([]),
});

const chatSchema = z.object({
  message: z.string().min(1).max(500),
  type:    z.enum(['text', 'emoji']).default('text'),
  isHost:  z.boolean().default(false),
});

async function listSessions(req, res, next) {
  try {
    const data = await cacheAside('live:sessions:active', () => svc.getActiveSessions(), 20);
    res.json(data);
  } catch (e) { next(e); }
}

async function getSession(req, res, next) {
  try {
    const data = await cacheAside(`live:session:${req.params.id}`, () => svc.getSessionById(req.params.id), 10);
    res.json(data);
  } catch (e) { next(e); }
}

async function startSession(req, res, next) {
  try {
    const body   = startSchema.parse(req.body);
    const result = await svc.startSession(req.user.id, body);
    res.json(result);
  } catch (e) { next(e); }
}

async function endSession(req, res, next) {
  try {
    const data = await svc.endSession(req.params.id, req.user.id, req.user.role);
    res.json(data);
  } catch (e) { next(e); }
}

async function joinSession(req, res, next) {
  try {
    await svc.joinSession(req.params.id, req.user.id);
    res.status(204).send();
  } catch (e) { next(e); }
}

async function leaveSession(req, res, next) {
  try {
    await svc.leaveSession(req.params.id, req.user.id);
    res.status(204).send();
  } catch (e) { next(e); }
}

async function likeSession(req, res, next) {
  try {
    await svc.likeSession(req.params.id);
    res.status(204).send();
  } catch (e) { next(e); }
}

async function sendChat(req, res, next) {
  try {
    const body = chatSchema.parse(req.body);
    const data = await svc.sendChatMessage(req.params.id, req.user, body);
    res.status(201).json(data);
  } catch (e) { next(e); }
}

async function getChats(req, res, next) {
  try {
    const limit = Math.min(parseInt(req.query.limit) || 50, 100);
    const data  = await svc.getRecentChats(req.params.id, limit);
    res.json(data);
  } catch (e) { next(e); }
}

async function getStats(req, res, next) {
  try {
    const data = await svc.getSessionStats(req.params.id);
    res.json(data);
  } catch (e) { next(e); }
}

const aiSuggestionSchema = z.object({
  productName:    z.string().max(200).optional(),
  category:       z.string().max(50).optional(),
  recentComments: z.array(z.string().max(500)).max(10).default([]),
});

async function getAiSuggestions(req, res, next) {
  try {
    const { productName: clientProductName, category: clientCategory, recentComments } = aiSuggestionSchema.parse(req.body);

    // Enrich với sản phẩm thực tế từ DB
    let productName = clientProductName;
    let category    = clientCategory;
    try {
      const session = await repo.findSessionById(req.params.id);
      if (session) {
        const products = (session.live_session_products || []);
        if (products.length > 0) {
          productName = products.map((p) => p.product_name).join(', ');
          category    = products[0].category || session.category || category;
        }
      }
    } catch (_) { /* fallback to client-provided values */ }

    const suggestions = await deepseek.getAiSuggestions(productName, category, recentComments);
    res.json({ suggestions });
  } catch (e) { next(e); }
}

const autoReplySchema = z.object({
  question:    z.string().min(1).max(500),
  productName: z.string().max(200).optional(),
  category:    z.string().max(50).optional(),
});

async function getAutoReply(req, res, next) {
  try {
    const { question, productName: clientProductName, category: clientCategory } = autoReplySchema.parse(req.body);

    // Luôn load sản phẩm từ DB để AI có đầy đủ context — không phụ thuộc client
    let productName = clientProductName || '';
    let category    = clientCategory    || '';
    try {
      const session = await repo.findSessionById(req.params.id);
      if (session) {
        const products = (session.live_session_products || []);
        if (products.length > 0) {
          productName = products.map((p) => p.product_name).join(', ');
          category    = products[0].category || session.category || category;
        } else if (!productName) {
          productName = session.title;
          category    = session.category || category;
        }
      }
    } catch (_) { /* fallback to client-provided values */ }

    if (!productName) {
      return res.status(400).json({ error: 'productName is required' });
    }

    const reply = await deepseek.getAutoReply(question, productName, category);
    res.json({ reply });
  } catch (e) { next(e); }
}

// POST /api/live/:id/track-cart-add — viewer thêm sản phẩm vào giỏ trong live
async function trackCartAdd(req, res, next) {
  try {
    await repo.incrementCartAdd(req.params.id);
    res.status(204).send();
  } catch (e) { next(e); }
}

// POST /api/live/:id/track-follow — viewer nhấn follow trong live
async function trackFollow(req, res, next) {
  try {
    await repo.incrementFollow(req.params.id);
    res.status(204).send();
  } catch (e) { next(e); }
}

// POST /api/live/:id/analyze — seller/admin phân tích kết quả buổi live
async function analyzeLive(req, res, next) {
  try {
    const session = await svc.getSessionById(req.params.id);
    const stats   = await svc.getSessionStats(req.params.id);
    const result  = await deepseek.analyzeLiveSentiment(stats, session.title);
    res.json(result);
  } catch (e) { next(e); }
}

// GET /api/live/:id/coupons — viewer lấy danh sách coupon active của shop
async function getSessionCoupons(req, res, next) {
  try {
    const data = await svc.getSessionCoupons(req.params.id);
    res.json(data);
  } catch (e) { next(e); }
}

// POST /api/live/:id/broadcast-coupon — host broadcast 1 coupon vào chat
async function broadcastCoupon(req, res, next) {
  try {
    const { couponCode } = z.object({ couponCode: z.string().min(1) }).parse(req.body);
    // Gửi như chat message từ bot
    const data = await svc.sendChatMessage(req.params.id, {
      id: req.user.id,
      fullName: 'Trợ lý Live',
    }, {
      message: `🎫 Coupon: ${couponCode.toUpperCase()} – Áp dụng khi đặt hàng!`,
      type: 'text',
    });
    res.status(201).json(data);
  } catch (e) { next(e); }
}

module.exports = {
  listSessions, getSession, startSession, endSession,
  joinSession, leaveSession, likeSession, sendChat,
  getChats, getStats, getAiSuggestions, getAutoReply,
  getSessionCoupons, broadcastCoupon,
  trackCartAdd, trackFollow, analyzeLive,
};
