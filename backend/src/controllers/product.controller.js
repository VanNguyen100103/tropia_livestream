'use strict';

const { z }  = require('zod');
const svc    = require('../services/product.service');
const { cacheAside } = require('../lib/redis');
const { NotFoundError } = require('../errors/AppError');

// ── Schemas ───────────────────────────────────────────────────────────────────

const variantSchema = z.object({
  attributeValueIds: z.array(z.string().uuid()).min(1),
  sku:        z.string().max(100).optional().nullable(),
  price:      z.number().int().min(0),
  sale_price: z.number().int().min(0).optional().nullable(),
  stock:      z.number().int().min(0).default(0),
  images:     z.array(z.string().url()).max(5).default([]),
  is_active:  z.boolean().optional(),
});

const productSchema = z.object({
  // Nhiều danh mục – bắt buộc có ít nhất 1
  categoryIds:       z.array(z.string().uuid()).min(1).max(5),
  primaryCategoryId: z.string().uuid().optional(),  // nếu không set → dùng categoryIds[0]

  name:         z.string().min(2).max(255),
  slug:         z.string().min(2).max(255).regex(/^[a-z0-9-]+$/),
  description:  z.string().max(10000).optional().nullable(),
  images:       z.array(z.string().url()).min(1).max(10),
  base_price:   z.number().int().min(0),
  sale_price:   z.number().int().min(0).optional().nullable(),
  unit:         z.string().max(20).default('cái'),
  has_variants: z.boolean().default(false),
  variants:     z.array(variantSchema).optional(),
});

// ── Controllers ───────────────────────────────────────────────────────────────

async function browseProducts(req, res, next) {
  try {
    res.json(await svc.browseProducts(req.query));
  } catch (e) { next(e); }
}

async function getProductBySlug(req, res, next) {
  try {
    const data = await cacheAside(`product:${req.params.slug}`, async () => {
      const repo = require('../repositories/product.repository');
      const d    = await repo.findProductBySlug(req.params.slug);
      if (!d) throw new NotFoundError('Product not found');
      return d;
    }, 30);
    res.json(data);
  } catch (e) { next(e); }
}

async function getProductsByShop(req, res, next) {
  try {
    res.json(await svc.getProductsByShop(req.params.shopId, req.query));
  } catch (e) { next(e); }
}

async function createProduct(req, res, next) {
  try {
    const body = productSchema.parse(req.body);
    res.status(201).json(await svc.createProduct(body, req.user.id));
  } catch (e) { next(e); }
}

// POST /api/products/quick-create — tạo nhanh sản phẩm đơn giản trong buổi live
// Không cần categoryIds/slug/variants — backend tự tạo slug và dùng category mặc định
const quickCreateSchema = z.object({
  name:        z.string().min(1).max(255),
  description: z.string().max(2000).optional().nullable(),
  price:       z.number().positive(),
  stock:       z.number().int().min(0).default(0),
  imageUrl:    z.string().url().optional().nullable(),
});

async function quickCreateProduct(req, res, next) {
  try {
    const { name, description, price, stock, imageUrl } = quickCreateSchema.parse(req.body);
    const result = await svc.quickCreateProduct(
      { name, description, price, stock, imageUrl },
      req.user.id,
    );
    res.status(201).json(result);
  } catch (e) { next(e); }
}

async function updateProduct(req, res, next) {
  try {
    const body = productSchema.partial().omit({ variants: true }).parse(req.body);
    res.json(await svc.updateProduct(req.params.id, body, req.user.id, req.user.role));
  } catch (e) { next(e); }
}

async function changeStatus(req, res, next) {
  try {
    const { status } = z.object({ status: z.enum(['draft', 'active', 'inactive']) }).parse(req.body);
    res.json(await svc.changeStatus(req.params.id, status, req.user.id, req.user.role));
  } catch (e) { next(e); }
}

async function deleteProduct(req, res, next) {
  try {
    await svc.deleteProduct(req.params.id, req.user.id, req.user.role);
    res.status(204).send();
  } catch (e) { next(e); }
}

async function addVariant(req, res, next) {
  try {
    const body = variantSchema.parse(req.body);
    res.status(201).json(await svc.addVariant(req.params.id, body, req.user.id, req.user.role));
  } catch (e) { next(e); }
}

async function updateVariant(req, res, next) {
  try {
    const body = variantSchema.partial().parse(req.body);
    res.json(await svc.updateVariant(req.params.id, req.params.variantId, body, req.user.id, req.user.role));
  } catch (e) { next(e); }
}

async function deleteVariant(req, res, next) {
  try {
    await svc.deleteVariant(req.params.id, req.params.variantId, req.user.id, req.user.role);
    res.status(204).send();
  } catch (e) { next(e); }
}

async function getSellerProducts(req, res, next) {
  try {
    res.json(await svc.getSellerProducts(req.user.id, req.query));
  } catch (e) { next(e); }
}

// ── Attribute types & values (admin) ─────────────────────────────────────────

async function listAttributeTypes(req, res, next) {
  try {
    res.json(await svc.listAttributeTypes());
  } catch (e) { next(e); }
}

async function createAttributeValue(req, res, next) {
  try {
    const body = z.object({
      attributeTypeId: z.string().uuid(),
      value:           z.string().min(1).max(100),
      displayName:     z.string().max(100).optional(),
      colorHex:        z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional(),
      sortOrder:       z.number().int().min(0).optional(),
    }).parse(req.body);
    res.status(201).json(await svc.createAttributeValue(body));
  } catch (e) { next(e); }
}

module.exports = {
  browseProducts, getProductBySlug, getProductsByShop,
  createProduct, quickCreateProduct, updateProduct, changeStatus, deleteProduct,
  addVariant, updateVariant, deleteVariant, getSellerProducts,
  listAttributeTypes, createAttributeValue,
};
