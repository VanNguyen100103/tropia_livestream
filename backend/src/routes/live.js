'use strict';

const { Router } = require('express');
const { authenticate, authorize } = require('../middleware/auth');
const { rateLimiter }             = require('../lib/redis');
const ctrl                        = require('../controllers/live.controller');

const router    = Router();
const apiLimit  = rateLimiter({ max: 300, windowMs: 60_000 });
const chatLimit = rateLimiter({ max: 30,  windowMs: 60_000 });

router.get('/',         apiLimit,                                        ctrl.listSessions);
router.get('/:id',      apiLimit,                                        ctrl.getSession);
router.post('/start',   authenticate, authorize('seller', 'admin'),      ctrl.startSession);
router.post('/:id/end', authenticate,                                    ctrl.endSession);
router.post('/:id/join',  authenticate,                                  ctrl.joinSession);
router.post('/:id/leave', authenticate,                                  ctrl.leaveSession);
router.post('/:id/like',                                                 ctrl.likeSession);
router.get ('/:id/chat',  apiLimit,                                      ctrl.getChats);
router.post('/:id/chat',  authenticate, chatLimit,                       ctrl.sendChat);
router.get ('/:id/stats', apiLimit,                                      ctrl.getStats);
router.post('/:id/ai-suggestions', authenticate, apiLimit,               ctrl.getAiSuggestions);
router.post('/:id/ai-reply',       authenticate, apiLimit,               ctrl.getAutoReply);
router.get ('/:id/coupons',        authenticate, apiLimit,               ctrl.getSessionCoupons);
router.post('/:id/broadcast-coupon', authenticate, authorize('seller', 'admin'), chatLimit, ctrl.broadcastCoupon);
router.post('/:id/track-cart-add',   authenticate,                               ctrl.trackCartAdd);
router.post('/:id/track-follow',     authenticate,                               ctrl.trackFollow);
router.post('/:id/analyze',          authenticate, authorize('seller', 'admin'), ctrl.analyzeLive);

module.exports = router;
