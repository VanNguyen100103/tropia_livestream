'use strict';

const express = require('express');
const { authenticate }  = require('../middleware/auth');
const { rateLimiter }   = require('../lib/redis');
const ctrl              = require('../controllers/order.controller');

const router = express.Router();

const orderLimit = rateLimiter({ max: 10, windowMs: 60_000, keyFn: req => req.user?.id, failClosed: true });

router.post('/',            authenticate, orderLimit, ctrl.placeOrder);
router.post('/checkout',    authenticate, orderLimit, ctrl.checkoutCart);
router.get('/my/list',      authenticate,             ctrl.getMyOrders);
router.get('/:sessionId',   authenticate,             ctrl.getSessionOrders);

module.exports = router;
