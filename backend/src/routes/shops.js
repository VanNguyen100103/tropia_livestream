'use strict';

const { Router } = require('express');
const { authenticate, optionalAuth, authorize } = require('../middleware/auth');
const ctrl                        = require('../controllers/shop.controller');

const router = Router();

router.get('/',                    ctrl.listShops);
router.get('/me/info',             authenticate, authorize('seller', 'admin'), ctrl.getMyShop);
router.get('/me/following',        authenticate, ctrl.getFollowedShops);
router.get('/:slug',               optionalAuth,  ctrl.getShopBySlug);
router.post('/',                   authenticate, authorize('seller', 'admin'), ctrl.createShop);
router.patch('/:id',               authenticate, authorize('seller', 'admin'), ctrl.updateShop);
router.get('/:id/follow-status',   authenticate, ctrl.getFollowStatus);
router.post('/:id/follow',         authenticate, ctrl.followShop);
router.delete('/:id/follow',       authenticate, ctrl.unfollowShop);

module.exports = router;
