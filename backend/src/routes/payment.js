'use strict';

const express = require('express');
const { authenticate }  = require('../middleware/auth');
const { rateLimiter }   = require('../lib/redis');
const ctrl              = require('../controllers/payment.controller');

const router = express.Router();

const paymentLimit = rateLimiter({ max: 10, windowMs: 60_000, failClosed: true });

router.post('/momo',               authenticate, paymentLimit, ctrl.initMomo);
router.get('/momo/callback',                                   ctrl.momoCallback);
router.get('/momo/result',                                     ctrl.momoResult);
router.post('/momo/ipn',                                       ctrl.momoIpn);
router.post('/momo/check',         authenticate,               ctrl.checkMomo);

router.post('/zalopay',            authenticate, paymentLimit, ctrl.initZalo);
router.post('/zalopay/callback',                               ctrl.zaloCallback);
router.post('/zalopay/check',      authenticate,               ctrl.checkZalo);

router.post('/vnpay',              authenticate, paymentLimit, ctrl.initVnpay);
router.get('/vnpay/return',                                    ctrl.vnpayReturn);
router.get('/vnpay/result',                                    ctrl.vnpayResult);

module.exports = router;
