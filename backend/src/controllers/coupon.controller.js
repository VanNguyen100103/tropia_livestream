'use strict';

const { z }  = require('zod');
const svc    = require('../services/coupon.service');

const couponSchema = z.object({
  code:           z.string().min(3).max(50).regex(/^[A-Z0-9_-]+$/i, 'Chỉ gồm chữ, số, _ hoặc -'),
  discount_type:  z.enum(['percent', 'fixed']).default('percent'),
  discount_value: z.number().positive(),
  min_order_value: z.number().min(0).default(0),
  max_discount:    z.number().positive().optional().nullable(),
  max_uses:        z.number().int().positive().optional().nullable(),
  expires_at:      z.string().datetime(),
  is_active:       z.boolean().default(true),
});

// GET /api/coupons  (admin)
async function listCoupons(req, res, next) {
  try {
    const result = await svc.listCoupons(req.query);
    res.json(result);
  } catch (e) { next(e); }
}

// POST /api/coupons/validate  (buyer – kiểm tra trước khi đặt hàng)
async function validateCoupon(req, res, next) {
  try {
    const { code, orderTotal } = z.object({
      code:       z.string(),
      orderTotal: z.number().positive(),
    }).parse(req.body);

    const result = await svc.validateCoupon(code, req.user.id, orderTotal);
    res.json({
      couponId:       result.coupon.id,
      code:           result.coupon.code,
      discountType:   result.coupon.discount_type,
      discountValue:  result.coupon.discount_value,
      discountAmount: result.discountAmount,
      finalPrice:     result.finalPrice,
    });
  } catch (e) { next(e); }
}

// POST /api/coupons  (admin)
async function createCoupon(req, res, next) {
  try {
    const body = couponSchema.parse(req.body);
    const data = await svc.createCoupon(body, req.user.id);
    res.status(201).json(data);
  } catch (e) { next(e); }
}

// PATCH /api/coupons/:id  (admin)
async function updateCoupon(req, res, next) {
  try {
    const body = couponSchema.partial().parse(req.body);
    const data = await svc.updateCoupon(req.params.id, body);
    res.json(data);
  } catch (e) { next(e); }
}

// DELETE /api/coupons/:id  (admin – deactivate, không xoá)
async function deactivateCoupon(req, res, next) {
  try {
    await svc.deactivateCoupon(req.params.id);
    res.status(204).send();
  } catch (e) { next(e); }
}

// GET /api/coupons/available  (buyer – platform coupons không gắn session)
async function getAvailableCoupons(req, res, next) {
  try {
    const data = await svc.getAvailableCoupons();
    res.json({ data });
  } catch (e) { next(e); }
}

// GET /api/coupons/shop/:shopId  (buyer – coupons của shop từ live sessions)
async function getShopCoupons(req, res, next) {
  try {
    const data = await svc.getShopCoupons(req.params.shopId);
    res.json({ data });
  } catch (e) { next(e); }
}

// GET /api/coupons/mine  (seller – lấy coupon do mình tạo để chọn cho buổi live)
async function getMyCoupons(req, res, next) {
  try {
    const repo = require('../repositories/coupon.repository');
    const data = await repo.listSellerCoupons(req.user.id);
    res.json({ data });
  } catch (e) { next(e); }
}

module.exports = { listCoupons, validateCoupon, createCoupon, updateCoupon, deactivateCoupon, getAvailableCoupons, getShopCoupons, getMyCoupons };
