'use strict';

const { invalidatePattern } = require('../lib/redis');
const { NotFoundError, ConflictError, ForbiddenError } = require('../errors/AppError');
const repo = require('../repositories/product.repository');

async function browseProducts(query) {
  const page   = Math.max(1, parseInt(query.page    || '1',  10));
  const limit  = Math.min(100, Math.max(1, parseInt(query.limit || '20', 10)));
  const offset = (page - 1) * limit;
  const { data, count } = await repo.browseProducts({ offset, limit, ...query });
  return { data, pagination: { page, limit, total: count, totalPages: Math.ceil(count / limit) } };
}

async function getProductsByShop(shopId, query) {
  const page   = Math.max(1, parseInt(query.page  || '1',  10));
  const limit  = Math.min(100, Math.max(1, parseInt(query.limit || '20', 10)));
  const offset = (page - 1) * limit;
  const { data, count } = await repo.findProductsByShop({ shopId, offset, limit });
  return { data, pagination: { page, limit, total: count, totalPages: Math.ceil(count / limit) } };
}

async function createProduct(body, userId) {
  const shopRepo = require('../repositories/shop.repository');
  const shop     = await shopRepo.findShopBySeller(userId);
  if (!shop) throw new NotFoundError('Bạn chưa có shop. Tạo shop trước!');
  if (await repo.slugExists(body.slug)) throw new ConflictError('Slug sản phẩm đã tồn tại');

  const { variants, categoryIds, primaryCategoryId, ...productData } = body;
  const product = await repo.createProduct({ ...productData, shop_id: shop.id, status: 'draft' });

  // Gán nhiều danh mục
  if (categoryIds?.length) {
    await repo.setProductCategories(product.id, categoryIds, primaryCategoryId);
  }

  // Tạo variants với attributes có cấu trúc
  if (body.has_variants && variants?.length) {
    await repo.createVariants(product.id, variants);
  }

  return repo.findProductWithVariants(product.id);
}

async function assertOwner(productId, userId, role) {
  const data = await repo.assertProductOwner(productId);
  if (!data) throw new NotFoundError('Product not found');
  if (role !== 'admin' && data.shops.seller_id !== userId) {
    throw new ForbiddenError('Không có quyền chỉnh sửa sản phẩm này');
  }
  return data;
}

async function updateProduct(productId, body, userId, role) {
  await assertOwner(productId, userId, role);
  if (body.slug && await repo.slugExists(body.slug, productId)) {
    throw new ConflictError('Slug đã tồn tại');
  }

  const { categoryIds, primaryCategoryId, ...productData } = body;
  const data = await repo.updateProduct(productId, productData);

  if (categoryIds !== undefined) {
    await repo.setProductCategories(productId, categoryIds, primaryCategoryId);
  }

  await invalidatePattern('product:*');
  return data;
}

async function changeStatus(productId, status, userId, role) {
  await assertOwner(productId, userId, role);
  const data = await repo.updateProduct(productId, { status });
  await invalidatePattern('product:*');
  return data;
}

async function deleteProduct(productId, userId, role) {
  await assertOwner(productId, userId, role);
  await repo.softDeleteProduct(productId);
  await invalidatePattern('product:*');
}

async function addVariant(productId, variantData, userId, role) {
  await assertOwner(productId, userId, role);
  const data = await repo.createVariant(productId, variantData);
  await invalidatePattern('product:*');
  return data;
}

async function updateVariant(productId, variantId, body, userId, role) {
  await assertOwner(productId, userId, role);
  const data = await repo.updateVariant(productId, variantId, body);
  if (!data) throw new NotFoundError('Variant not found');
  await invalidatePattern('product:*');
  return data;
}

async function deleteVariant(productId, variantId, userId, role) {
  await assertOwner(productId, userId, role);
  await repo.deleteVariant(productId, variantId);
  await invalidatePattern('product:*');
}

async function getSellerProducts(userId, query) {
  const shopRepo = require('../repositories/shop.repository');
  const shop     = await shopRepo.findShopBySeller(userId);
  if (!shop) return { data: [], pagination: { total: 0 } };

  const page   = Math.max(1, parseInt(query.page  || '1',  10));
  const limit  = Math.min(100, Math.max(1, parseInt(query.limit || '20', 10)));
  const offset = (page - 1) * limit;
  const { data, count } = await repo.findSellerProducts({ shopId: shop.id, offset, limit, status: query.status });
  return { data, pagination: { page, limit, total: count, totalPages: Math.ceil(count / limit) } };
}

async function listAttributeTypes() {
  return repo.listAttributeTypes();
}

async function createAttributeValue(body) {
  return repo.createAttributeValue(body);
}

// Tạo nhanh sản phẩm đơn giản trong buổi live (không cần categoryIds/slug/variants)
async function quickCreateProduct({ name, description, price, stock, imageUrl }, userId) {
  const shopRepo = require('../repositories/shop.repository');
  const shop     = await shopRepo.findShopBySeller(userId);
  if (!shop) throw new NotFoundError('Bạn chưa có shop. Tạo shop trước!');

  // Tạo slug duy nhất từ tên + timestamp
  const base = name
    .toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/đ/g, 'd').replace(/[^a-z0-9\s-]/g, '')
    .trim().replace(/\s+/g, '-')
    .substring(0, 50);
  const slug = `${base}-${Date.now()}`;

  const product = await repo.createProduct({
    name,
    slug,
    description:  description || null,
    images:       imageUrl ? [imageUrl] : [],
    base_price:   Math.round(price),
    sale_price:   null,
    unit:         'cái',
    has_variants: false,
    shop_id:      shop.id,
    status:       'active',
  });

  // Tạo default variant (stock)
  await repo.createDefaultVariant(product.id, Math.round(price), stock);

  return repo.findProductWithVariants(product.id);
}

module.exports = {
  browseProducts, getProductsByShop, createProduct, quickCreateProduct,
  updateProduct, changeStatus, deleteProduct,
  addVariant, updateVariant, deleteVariant, getSellerProducts,
  listAttributeTypes, createAttributeValue,
};
