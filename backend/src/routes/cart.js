'use strict';

const { Router }    = require('express');
const { authenticate } = require('../middleware/auth');
const ctrl          = require('../controllers/cart.controller');

const router = Router();

// Tất cả cart routes yêu cầu đăng nhập
router.use(authenticate);

router.get('/',                    ctrl.getCart);
router.post('/items',              ctrl.addItem);
router.post('/items/from-live',    ctrl.addItemFromLive);
router.patch('/items/:id/qty',     ctrl.updateQuantity);
router.patch('/items/:id/select',  ctrl.updateSelected);
router.patch('/select-all',        ctrl.selectAll);
router.delete('/items/:id',        ctrl.removeItem);
router.delete('/items/selected',   ctrl.removeSelected);

module.exports = router;
