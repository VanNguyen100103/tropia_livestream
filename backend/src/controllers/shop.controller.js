'use strict';

const { z }  = require('zod');
const svc    = require('../services/shop.service');
const { cacheAside } = require('../lib/redis');

const shopSchema = z.object({
  name:        z.string().min(2).max(100),
  slug:        z.string().min(2).max(100).regex(/^[a-z0-9-]+$/),
  description: z.string().max(2000).optional().nullable(),
  logo_url:    z.string().url().optional().nullable(),
  banner_url:  z.string().url().optional().nullable(),
});

async function listShops(req, res, next) {
  try {
    const result = await svc.listShops(req.query);
    res.json(result);
  } catch (e) { next(e); }
}

async function getShopBySlug(req, res, next) {
  try {
    const repo = require('../repositories/shop.repository');
    const shop = await svc.getShopBySlug(req.params.slug);
    const following = req.user
      ? await repo.isFollowing(req.user.id, shop.id)
      : false;
    res.json({ ...shop, is_following: following });
  } catch (e) { next(e); }
}

async function getMyShop(req, res, next) {
  try {
    const repo = require('../repositories/shop.repository');
    const data = await repo.findShopBySeller(req.user.id);
    res.json(data || null);
  } catch (e) { next(e); }
}

async function createShop(req, res, next) {
  try {
    const body = shopSchema.parse(req.body);
    const data = await svc.createShop(body, req.user.id);
    res.status(201).json(data);
  } catch (e) { next(e); }
}

async function updateShop(req, res, next) {
  try {
    const body = shopSchema.partial().parse(req.body);
    const data = await svc.updateShop(req.params.id, body, req.user.id, req.user.role);
    res.json(data);
  } catch (e) { next(e); }
}

// Resolve shopId: nếu :id là seller_id (profile UUID), tìm shops.id tương ứng
async function resolveShopId(rawId) {
  const repo = require('../repositories/shop.repository');
  // Thử tìm theo shops.id trước
  const byId = await repo.findShopBySlug(rawId); // hỗ trợ UUID → id hoặc seller_id
  return byId ? byId.id : rawId;
}

async function followShop(req, res, next) {
  try {
    const repo   = require('../repositories/shop.repository');
    const shopId = await resolveShopId(req.params.id);
    await repo.followShop(req.user.id, shopId);
    res.json({ followed: true });
  } catch (e) { next(e); }
}

async function unfollowShop(req, res, next) {
  try {
    const repo   = require('../repositories/shop.repository');
    const shopId = await resolveShopId(req.params.id);
    await repo.unfollowShop(req.user.id, shopId);
    res.json({ followed: false });
  } catch (e) { next(e); }
}

async function getFollowStatus(req, res, next) {
  try {
    const repo     = require('../repositories/shop.repository');
    const shopId   = await resolveShopId(req.params.id);
    const followed = await repo.isFollowing(req.user.id, shopId);
    res.json({ followed });
  } catch (e) { next(e); }
}

async function getFollowedShops(req, res, next) {
  try {
    const repo   = require('../repositories/shop.repository');
    const offset = Number(req.query.offset) || 0;
    const limit  = Math.min(Number(req.query.limit) || 20, 50);
    const result = await repo.getFollowedShops(req.user.id, { offset, limit });
    res.json(result);
  } catch (e) { next(e); }
}

module.exports = {
  listShops, getShopBySlug, getMyShop, createShop, updateShop,
  followShop, unfollowShop, getFollowStatus, getFollowedShops,
};
