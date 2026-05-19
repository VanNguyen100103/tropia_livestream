'use strict';

const { Router } = require('express');
const { authenticate, authorize } = require('../middleware/auth');
const ctrl                        = require('../controllers/product.controller');

const router = Router();

// attributes (public read, admin write)
router.get('/attributes',      ctrl.listAttributeTypes);
router.post('/attributes/values', authenticate, authorize('admin'), ctrl.createAttributeValue);

// public
router.get('/',                ctrl.browseProducts);
router.get('/seller/list',     authenticate, authorize('seller', 'admin'), ctrl.getSellerProducts);
router.get('/shop/:shopId',    ctrl.getProductsByShop);
router.get('/:slug',           ctrl.getProductBySlug);

// seller / admin
router.post('/quick-create',   authenticate, authorize('seller', 'admin'), ctrl.quickCreateProduct);
router.post('/',               authenticate, authorize('seller', 'admin'), ctrl.createProduct);
router.patch('/:id',           authenticate, authorize('seller', 'admin'), ctrl.updateProduct);
router.patch('/:id/status',    authenticate, authorize('seller', 'admin'), ctrl.changeStatus);
router.delete('/:id',          authenticate, authorize('seller', 'admin'), ctrl.deleteProduct);
router.post('/:id/variants',             authenticate, authorize('seller', 'admin'), ctrl.addVariant);
router.patch('/:id/variants/:variantId', authenticate, authorize('seller', 'admin'), ctrl.updateVariant);
router.delete('/:id/variants/:variantId',authenticate, authorize('seller', 'admin'), ctrl.deleteVariant);

module.exports = router;
