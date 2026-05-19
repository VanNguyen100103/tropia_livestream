'use strict';

const { Router } = require('express');
const { authenticate, authorize } = require('../middleware/auth');
const { rateLimiter }             = require('../lib/redis');
const ctrl                        = require('../controllers/coupon.controller');

const router     = Router();
const checkLimit = rateLimiter({ max: 20, windowMs: 60_000 });

router.post('/validate',        authenticate, checkLimit,           ctrl.validateCoupon);
router.get('/available',        authenticate,                        ctrl.getAvailableCoupons);
router.get('/shop/:shopId',     authenticate,                        ctrl.getShopCoupons);
router.get('/',                 authenticate, authorize('admin'),    ctrl.listCoupons);
router.post('/',                authenticate, authorize('admin'),    ctrl.createCoupon);
router.patch('/:id',            authenticate, authorize('admin'),    ctrl.updateCoupon);
router.delete('/:id',           authenticate, authorize('admin'),    ctrl.deactivateCoupon);

module.exports = router;
