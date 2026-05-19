'use strict';

const { signAccessToken } = require('../../src/middleware/auth');

function makeToken(overrides = {}) {
  return signAccessToken({
    id:       overrides.id    ?? 'user-uuid-001',
    role:     overrides.role  ?? 'buyer',
    email:    overrides.email ?? 'test@tropia.vn',
    fullName: overrides.name  ?? 'Test User',
  });
}

function bearerHeader(overrides = {}) {
  return { Authorization: `Bearer ${makeToken(overrides)}` };
}

module.exports = { makeToken, bearerHeader };
