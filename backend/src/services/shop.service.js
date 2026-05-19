'use strict';

const { invalidatePattern } = require('../lib/redis');
const { NotFoundError, ConflictError, ForbiddenError } = require('../errors/AppError');
const repo = require('../repositories/shop.repository');

async function listShops(query) {
  const page   = Math.max(1, parseInt(query.page  || '1', 10));
  const limit  = Math.min(50, Math.max(1, parseInt(query.limit || '20', 10)));
  const offset = (page - 1) * limit;
  const { data, count } = await repo.listShops({ offset, limit });
  return { data, pagination: { page, limit, total: count, totalPages: Math.ceil(count / limit) } };
}

async function getShopBySlug(slug) {
  const data = await repo.findShopBySlug(slug);
  if (!data) throw new NotFoundError('Shop not found');
  return data;
}

async function createShop(body, sellerId) {
  if (await repo.sellerHasShop(sellerId)) throw new ConflictError('Bạn đã có shop rồi');
  if (await repo.slugExists(body.slug))   throw new ConflictError('Slug đã được dùng');
  return repo.createShop(body, sellerId);
}

async function updateShop(shopId, body, userId, role) {
  const shop = await repo.findShopById(shopId);
  if (!shop) throw new NotFoundError('Shop not found');
  if (shop.seller_id !== userId && role !== 'admin') {
    throw new ForbiddenError('Không có quyền chỉnh sửa shop này');
  }
  if (body.slug && await repo.slugExists(body.slug, shopId)) {
    throw new ConflictError('Slug đã được dùng');
  }
  const data = await repo.updateShop(shopId, body);
  await invalidatePattern('shop:*');
  return data;
}

module.exports = { listShops, getShopBySlug, createShop, updateShop };
