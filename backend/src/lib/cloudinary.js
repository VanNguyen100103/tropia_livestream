'use strict';

const cloudinary = require('cloudinary').v2;
const multer     = require('multer');
const cfg        = require('../config').cloudinary;

cloudinary.config({
  cloud_name: cfg.cloudName,
  api_key:    cfg.apiKey,
  api_secret: cfg.apiSecret,
});

// Multer: lưu trong memory, mỗi file tối đa 5MB, tổng cộng tối đa 10 file
const upload = multer({
  storage: multer.memoryStorage(),
  limits:  { fileSize: 5 * 1024 * 1024, files: 10 },
  fileFilter(_req, file, cb) {
    if (!file.mimetype.startsWith('image/')) {
      return cb(new Error('Chỉ chấp nhận file ảnh'));
    }
    cb(null, true);
  },
});

/**
 * Upload buffer lên Cloudinary.
 * @param {Buffer} buffer
 * @param {object} opts  – folder, public_id, transformation, ...
 * @returns {Promise<object>} cloudinary upload result
 */
function uploadBuffer(buffer, opts = {}) {
  return new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      {
        folder:            opts.folder      || 'tropia',
        allowed_formats:   ['jpg', 'jpeg', 'png', 'webp'],
        transformation:    opts.transformation || [{ quality: 'auto', fetch_format: 'auto' }],
        overwrite:         opts.overwrite   ?? true,
        ...(opts.public_id ? { public_id: opts.public_id } : {}),
      },
      (err, result) => (err ? reject(err) : resolve(result)),
    );
    stream.end(buffer);
  });
}

/**
 * Xoá ảnh trên Cloudinary theo public_id.
 */
function deleteImage(publicId) {
  return cloudinary.uploader.destroy(publicId);
}

module.exports = { upload, uploadBuffer, deleteImage, cloudinary };
