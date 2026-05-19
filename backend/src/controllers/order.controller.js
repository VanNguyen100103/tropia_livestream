'use strict';

const { z }    = require('zod');
const svc      = require('../services/order.service');
const cartSvc  = require('../services/cart.checkout.service');

const placeOrderSchema = z.object({
  sessionId:   z.string().uuid(),
  productId:   z.string().uuid(),
  quantity:    z.number().int().min(1).max(99).default(1),
  buyerName:   z.string().min(1).max(100),
  buyerAvatar: z.string().url().optional().nullable(),
  couponCode:  z.string().optional().nullable(),
});

async function placeOrder(req, res, next) {
  try {
    const { sessionId, productId, quantity, buyerName, buyerAvatar, couponCode } = placeOrderSchema.parse(req.body);
    const { order, product, discountAmount } = await svc.placeOrder({
      sessionId, productId, buyerId: req.user.id,
      buyerName, buyerAvatar, quantity, couponCode,
    });
    res.status(201).json({
      order,
      product: {
        name:           product.product_name,
        unitPrice:      product.sale_price,
        originalTotal:  product.sale_price * quantity,
        discountAmount: discountAmount || 0,
        finalTotal:     order.total_price,
      },
    });
  } catch (e) { next(e); }
}

// ── Checkout từ giỏ hàng thường (không bắt buộc live session) ────────────────

const checkoutSchema = z.object({
  items: z.array(z.object({
    cartItemId: z.string().uuid(),
    variantId:  z.string().uuid(),
    quantity:   z.number().int().min(1).max(999),
    unitPrice:  z.number().int().min(0),
    productName: z.string(),
    sessionId:  z.string().uuid().optional().nullable(),
  })).min(1),
  couponCode:     z.string().optional().nullable(),
  discountAmount: z.number().int().min(0).optional().nullable(), // tổng discount từ client
  paymentMethod:  z.enum(['cod', 'momo', 'zalopay', 'vnpay']).default('cod'),
  note:           z.string().max(500).optional().nullable(),
});

async function checkoutCart(req, res, next) {
  try {
    const body = checkoutSchema.parse(req.body);
    const result = await cartSvc.checkoutCart({
      ...body,
      buyerId:   req.user.id,
      buyerName: req.user.name || req.user.email || 'Khách',
    });
    res.status(201).json(result);
  } catch (e) { next(e); }
}

async function getSessionOrders(req, res, next) {
  try {
    const data = await svc.getSessionOrders(req.params.sessionId, req.user.id, req.user.role);
    res.json(data);
  } catch (e) { next(e); }
}

async function getMyOrders(req, res, next) {
  try {
    const page  = Math.max(1, parseInt(req.query.page  || '1',  10));
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit || '20', 10)));
    const result = await svc.getMyOrders(req.user.id, page, limit);
    res.json(result);
  } catch (e) { next(e); }
}

module.exports = { placeOrder, checkoutCart, getSessionOrders, getMyOrders };
