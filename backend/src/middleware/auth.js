'use strict';

const jwt    = require('jsonwebtoken');
const config = require('../config');
const { AuthError, ForbiddenError } = require('../errors/AppError');

function signAccessToken(payload) {
  return jwt.sign(payload, config.jwt.accessSecret, {
    expiresIn: config.jwt.accessExpiresIn,
    issuer:    'tropia',
    audience:  'tropia-client',
  });
}

function signRefreshToken(payload) {
  return jwt.sign(payload, config.jwt.refreshSecret, {
    expiresIn: config.jwt.refreshExpiresIn,
    issuer:    'tropia',
  });
}

function verifyAccessToken(token) {
  return jwt.verify(token, config.jwt.accessSecret, { issuer: 'tropia', audience: 'tropia-client' });
}

function verifyRefreshToken(token) {
  return jwt.verify(token, config.jwt.refreshSecret, { issuer: 'tropia' });
}

// Require valid Bearer token – attaches req.user
function authenticate(req, res, next) {
  const auth = req.headers.authorization;
  if (!auth?.startsWith('Bearer ')) return next(new AuthError('Authentication required'));

  try {
    req.user = verifyAccessToken(auth.slice(7));
    next();
  } catch {
    next(new AuthError('Invalid or expired token'));
  }
}

// Soft auth – attaches req.user if token present but does NOT block
function optionalAuth(req, _res, next) {
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) {
    try { req.user = verifyAccessToken(auth.slice(7)); } catch { /* ignore */ }
  }
  next();
}

// RBAC – use after authenticate
function authorize(...roles) {
  return (req, _res, next) => {
    if (!req.user) return next(new AuthError('Authentication required'));
    if (!roles.includes(req.user.role)) return next(new ForbiddenError('Insufficient permissions'));
    next();
  };
}

module.exports = { signAccessToken, signRefreshToken, verifyAccessToken, verifyRefreshToken, authenticate, optionalAuth, authorize };
