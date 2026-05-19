'use strict';

const { Router }                  = require('express');
const { authenticate, authorize } = require('../middleware/auth');
const { upload, uploadBuffer }    = require('../lib/cloudinary');
const { AppError }                = require('../errors/AppError');

const router = Router();

// ── POST /api/upload/avatar ───────────────────────────────────────────────────
// tropia/avatars/avatar_{userId}  (overwrite – 1 file duy nhất mỗi user)
router.post(
  '/avatar',
  authenticate,
  upload.single('image'),
  async (req, res, next) => {
    try {
      if (!req.file) throw new AppError('Không tìm thấy file ảnh', 400);

      const result = await uploadBuffer(req.file.buffer, {
        folder:    'tropia/avatars',
        public_id: `avatar_${req.user.id}`,
        overwrite: true,
        transformation: [
          { width: 400, height: 400, crop: 'fill', gravity: 'face' },
          { quality: 'auto', fetch_format: 'auto' },
        ],
      });

      res.json({ url: result.secure_url, publicId: result.public_id });
    } catch (err) { next(err); }
  },
);

// ── POST /api/upload/product ──────────────────────────────────────────────────
// Upload nhiều ảnh sản phẩm cùng lúc (tối đa 10 file)
// tropia/products/product_{productId}_{index}
// Body (form-data): productId, files field: "images"
router.post(
  '/product',
  authenticate,
  authorize('seller', 'admin'),
  upload.array('images', 10),
  async (req, res, next) => {
    try {
      if (!req.files?.length) throw new AppError('Không tìm thấy file ảnh', 400);
      const { productId } = req.body;
      if (!productId) throw new AppError('productId là bắt buộc', 400);

      const results = await Promise.all(
        req.files.map((file, idx) =>
          uploadBuffer(file.buffer, {
            folder:    'tropia/products',
            public_id: `product_${productId}_${idx}`,
            overwrite: true,
            transformation: [
              { width: 800, height: 800, crop: 'limit' },
              { quality: 'auto', fetch_format: 'auto' },
            ],
          }),
        ),
      );

      res.json(results.map(r => ({ url: r.secure_url, publicId: r.public_id })));
    } catch (err) { next(err); }
  },
);

// ── POST /api/upload/variant ──────────────────────────────────────────────────
// Upload nhiều ảnh cho 1 variant (tối đa 5 file)
// tropia/products/variants/variant_{variantId}_{index}
// Body (form-data): variantId, files field: "images"
router.post(
  '/variant',
  authenticate,
  authorize('seller', 'admin'),
  upload.array('images', 5),
  async (req, res, next) => {
    try {
      if (!req.files?.length) throw new AppError('Không tìm thấy file ảnh', 400);
      const { variantId } = req.body;
      if (!variantId) throw new AppError('variantId là bắt buộc', 400);

      const results = await Promise.all(
        req.files.map((file, idx) =>
          uploadBuffer(file.buffer, {
            folder:    'tropia/products/variants',
            public_id: `variant_${variantId}_${idx}`,
            overwrite: true,
            transformation: [
              { width: 800, height: 800, crop: 'limit' },
              { quality: 'auto', fetch_format: 'auto' },
            ],
          }),
        ),
      );

      res.json(results.map(r => ({ url: r.secure_url, publicId: r.public_id })));
    } catch (err) { next(err); }
  },
);

// ── POST /api/upload/shop ─────────────────────────────────────────────────────
// tropia/shops/shop_{shopId}  (overwrite – banner/logo shop)
// Body: { shopId }
router.post(
  '/shop',
  authenticate,
  authorize('seller', 'admin'),
  upload.single('image'),
  async (req, res, next) => {
    try {
      if (!req.file) throw new AppError('Không tìm thấy file ảnh', 400);
      const { shopId } = req.body;
      if (!shopId) throw new AppError('shopId là bắt buộc', 400);

      const result = await uploadBuffer(req.file.buffer, {
        folder:    'tropia/shops',
        public_id: `shop_${shopId}`,
        overwrite: true,
        transformation: [
          { width: 1200, height: 400, crop: 'fill' },
          { quality: 'auto', fetch_format: 'auto' },
        ],
      });

      res.json({ url: result.secure_url, publicId: result.public_id });
    } catch (err) { next(err); }
  },
);

// ── POST /api/upload/temp ─────────────────────────────────────────────────────
// Upload ảnh tạm cho quick-create product (trước khi có productId)
// tropia/products/temp_{userId}_{timestamp}
router.post(
  '/temp',
  authenticate,
  authorize('seller', 'admin'),
  upload.single('image'),
  async (req, res, next) => {
    try {
      if (!req.file) throw new AppError('Không tìm thấy file ảnh', 400);

      const result = await uploadBuffer(req.file.buffer, {
        folder:    'tropia/products',
        public_id: `temp_${req.user.id}_${Date.now()}`,
        overwrite: false,
        transformation: [
          { width: 800, height: 800, crop: 'limit' },
          { quality: 'auto', fetch_format: 'auto' },
        ],
      });

      res.json({ url: result.secure_url, publicId: result.public_id });
    } catch (err) { next(err); }
  },
);

// ── POST /api/upload/live ─────────────────────────────────────────────────────
// tropia/live/live_{sessionId}_{timestamp}  (không overwrite – thumbnail mỗi lần khác nhau)
// Body: { sessionId }
router.post(
  '/live',
  authenticate,
  authorize('seller', 'admin'),
  upload.single('image'),
  async (req, res, next) => {
    try {
      if (!req.file) throw new AppError('Không tìm thấy file ảnh', 400);
      const { sessionId } = req.body;
      if (!sessionId) throw new AppError('sessionId là bắt buộc', 400);

      const result = await uploadBuffer(req.file.buffer, {
        folder:    'tropia/live',
        public_id: `live_${sessionId}_${Date.now()}`,
        overwrite: false,
        transformation: [
          { width: 1280, height: 720, crop: 'fill' },
          { quality: 'auto', fetch_format: 'auto' },
        ],
      });

      res.json({ url: result.secure_url, publicId: result.public_id });
    } catch (err) { next(err); }
  },
);

module.exports = router;
