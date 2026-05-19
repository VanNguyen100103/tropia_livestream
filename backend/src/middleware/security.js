'use strict';

const helmet = require('helmet');
const { v4: uuidv4 } = require('uuid');
const logger = require('../lib/logger');

// ── API8: Helmet – security headers ───────────────────────────────────────────
const helmetConfig = () => helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc:             ["'self'"],
      scriptSrc:              ["'self'"],
      objectSrc:              ["'none'"],
      upgradeInsecureRequests: [],
    },
  },
  hsts:           { maxAge: 31_536_000, includeSubDomains: true, preload: true },
  referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
  // Ẩn X-Powered-By
  hidePoweredBy: true,
});

// ── Request ID (correlation ID cho tracing) ────────────────────────────────────
const requestId = () => (req, res, next) => {
  req.id = req.headers['x-request-id'] || uuidv4();
  res.setHeader('X-Request-ID', req.id);
  next();
};

// ── API8: Input sanitization – block prototype pollution + null bytes ──────────
const sanitizeInput = () => (req, _res, next) => {
  const BLOCKED_KEYS = new Set(['__proto__', 'constructor', 'prototype']);
  const clean = (obj) => {
    if (!obj || typeof obj !== 'object') return;
    for (const key of Object.keys(obj)) {
      if (BLOCKED_KEYS.has(key)) { delete obj[key]; continue; }
      if (typeof obj[key] === 'string') {
        // Null bytes + Unicode direction overrides (API8)
        obj[key] = obj[key].replace(/\0/g, '').replace(/[‮‏​]/g, '');
      } else if (typeof obj[key] === 'object') {
        clean(obj[key]);
      }
    }
  };
  clean(req.body);
  clean(req.query);
  next();
};

// ── API4: Payload size guard ───────────────────────────────────────────────────
const requestSizeGuard = (limitKb = 64) => (req, res, next) => {
  const len = parseInt(req.headers['content-length'] || '0', 10);
  if (len > limitKb * 1024) {
    return res.status(413).json({ error: 'Request too large', code: 'PAYLOAD_TOO_LARGE' });
  }
  next();
};

// ── API10: Audit logging – mọi request (không chỉ lỗi) ────────────────────────
const auditLog = () => (req, res, next) => {
  const start = Date.now();

  res.on('finish', () => {
    const ms     = Date.now() - start;
    const userId = req.user?.id ?? null;

    // Log tất cả — level tuỳ status code
    const entry = {
      method:    req.method,
      path:      req.path,
      status:    res.statusCode,
      ms,
      userId,
      requestId: req.id,
      // IP: lấy từ x-forwarded-for nếu qua proxy, ẩn octet cuối (GDPR)
      ip: _anonymizeIp(req.ip || req.socket.remoteAddress),
    };

    if (res.statusCode >= 500) return logger.error(entry, 'Server error');
    if (res.statusCode >= 400) return logger.warn(entry,  'Client error');

    // Chỉ log các security-sensitive actions ở level info
    const sensitiveRoutes = ['/api/auth/', '/api/orders', '/api/upload'];
    if (sensitiveRoutes.some(r => req.path.startsWith(r))) {
      logger.info(entry, 'Sensitive action');
    }
  });

  next();
};

// ── API10: Security event logger ──────────────────────────────────────────────
// Gọi trực tiếp từ route handlers cho các event quan trọng
function logSecurityEvent(event, data = {}) {
  logger.warn({ securityEvent: event, ...data }, `[SECURITY] ${event}`);
}

// Ẩn octet cuối của IPv4 (GDPR partial anonymization)
function _anonymizeIp(ip) {
  if (!ip) return null;
  const parts = ip.split('.');
  if (parts.length === 4) {
    parts[3] = '0';
    return parts.join('.');
  }
  return ip; // IPv6: giữ nguyên (không PII)
}

module.exports = { helmetConfig, requestId, sanitizeInput, requestSizeGuard, auditLog, logSecurityEvent };
