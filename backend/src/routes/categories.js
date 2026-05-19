'use strict';

const { Router } = require('express');
const { authenticate, authorize } = require('../middleware/auth');
const ctrl                        = require('../controllers/category.controller');

const router = Router();

router.get('/',         ctrl.listCategories);
router.get('/:slug',    ctrl.getCategoryBySlug);
router.post('/',        authenticate, authorize('admin'), ctrl.createCategory);
router.patch('/:id',    authenticate, authorize('admin'), ctrl.updateCategory);
router.delete('/:id',   authenticate, authorize('admin'), ctrl.deleteCategory);

module.exports = router;
