'use strict';

function _require(key) {
  const val = process.env[key];
  if (!val) throw new Error(`Missing required env var: ${key}`);
  return val;
}

module.exports = {
  jwt: {
    accessSecret:     _require('JWT_ACCESS_SECRET'),
    refreshSecret:    _require('JWT_REFRESH_SECRET'),
    accessExpiresIn:  process.env.JWT_ACCESS_EXPIRES_IN  || '15m',
    refreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '7d',
  },

  google: {
    clientId:     process.env.GOOGLE_CLIENT_ID,
    clientSecret: process.env.GOOGLE_CLIENT_SECRET,
    callbackUrl:  process.env.GOOGLE_CALLBACK_URL || 'http://localhost:3000/api/auth/google/callback',
    appDeepLink:  process.env.GOOGLE_APP_DEEP_LINK || 'tropia://auth/callback',
  },
};
