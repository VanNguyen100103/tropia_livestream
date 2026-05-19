'use strict';

const express  = require('express');
const passport = require('../lib/passport');
const { authenticate }  = require('../middleware/auth');
const { rateLimiter }   = require('../lib/redis');
const config            = require('../config');
const ctrl              = require('../controllers/auth.controller');

const router = express.Router();

const loginLimit    = rateLimiter({ max: 5,  windowMs: 60_000,  failClosed: true });
const registerLimit = rateLimiter({ max: 3,  windowMs: 300_000, failClosed: true });
const resetLimit    = rateLimiter({ max: 3,  windowMs: 300_000, failClosed: false });

router.post('/register',             registerLimit, ctrl.register);
router.post('/login',                loginLimit,    ctrl.login);
router.post('/refresh',                             ctrl.refresh);
router.post('/logout',                              ctrl.logout);
router.post('/logout-all',           authenticate,  ctrl.logoutAll);
router.get ('/me',                   authenticate,  ctrl.me);
router.post('/forgot-password',      resetLimit,    ctrl.forgotPassword);
router.post('/reset-password',       resetLimit,    ctrl.resetPassword);
router.post('/verify-otp',                          ctrl.verifyEmailOtp);
router.post('/resend-verify-email',  resetLimit,    ctrl.resendVerifyEmail);

router.get('/google',
  passport.authenticate('google', { session: false, scope: ['profile', 'email'] }),
);

router.get('/google/callback',
  passport.authenticate('google', {
    session: false,
    failureRedirect: `${config.google.appDeepLink}?error=google_auth_failed`,
  }),
  ctrl.googleCallback,
);

router.get('/google/exchange', ctrl.googleExchange);

module.exports = router;
