'use strict';

const { z }      = require('zod');
const svc        = require('../services/auth.service');
const passport   = require('../lib/passport');
const { logSecurityEvent } = require('../middleware/security');

const registerSchema = z.object({
  email:    z.string().email().max(255),
  password: z.string().min(8).max(72)
    .regex(/[A-Z]/, 'Phải có chữ in hoa')
    .regex(/[0-9]/, 'Phải có số'),
  fullName: z.string().min(2).max(100),
  phone:    z.string().regex(/^\+?[0-9]{7,15}$/).optional(),
  shopName: z.string().min(2).max(100).optional(),
  role:     z.enum(['buyer', 'seller']).default('buyer'),
});

const loginSchema = z.object({
  email:    z.string().email(),
  password: z.string().min(1),
});

async function register(req, res, next) {
  try {
    const body    = registerSchema.parse(req.body);
    const profile = await svc.register(body);
    res.status(201).json({ user: profile });
  } catch (e) { next(e); }
}

async function login(req, res, next) {
  try {
    const { email, password } = loginSchema.parse(req.body);
    const { tokens, user }    = await svc.login(email, password, req.ip);
    res.cookie('refresh_token', tokens.refreshToken, svc.cookieOpts());
    res.json({
      accessToken: tokens.accessToken,
      user: { id: user.id, email: user.email, name: user.name, role: user.role, avatarUrl: user.avatar_url },
    });
  } catch (e) { next(e); }
}

async function refresh(req, res, next) {
  try {
    const rawToken     = req.cookies?.refresh_token || req.body?.refreshToken;
    const { tokens, user } = await svc.refresh(rawToken);
    res.cookie('refresh_token', tokens.refreshToken, svc.cookieOpts());
    res.json({
      accessToken: tokens.accessToken,
      user: { id: user.id, email: user.email, name: user.name, role: user.role, avatarUrl: user.avatar_url },
    });
  } catch (e) { next(e); }
}

async function logout(req, res, next) {
  try {
    await svc.logout(req.cookies?.refresh_token);
    res.clearCookie('refresh_token', { path: '/api/auth' });
    res.status(204).send();
  } catch (e) { next(e); }
}

async function logoutAll(req, res, next) {
  try {
    await svc.logoutAll(req.user.id);
    res.clearCookie('refresh_token', { path: '/api/auth' });
    res.status(204).send();
  } catch (e) { next(e); }
}

const forgotSchema = z.object({ email: z.string().email() });
const resetSchema  = z.object({
  token:       z.string().min(10),
  newPassword: z.string().min(8).max(72)
    .regex(/[A-Z]/, 'Phải có chữ in hoa')
    .regex(/[0-9]/, 'Phải có số'),
});

async function forgotPassword(req, res, next) {
  try {
    const { email } = forgotSchema.parse(req.body);
    await svc.forgotPassword(email);
    // Always 200 to prevent email enumeration
    res.json({ message: 'Nếu email tồn tại, link đặt lại mật khẩu đã được gửi.' });
  } catch (e) { next(e); }
}

async function resetPassword(req, res, next) {
  try {
    const { token, newPassword } = resetSchema.parse(req.body);
    await svc.resetPassword(token, newPassword);
    res.json({ message: 'Mật khẩu đã được đặt lại thành công.' });
  } catch (e) { next(e); }
}

async function me(req, res, next) {
  try {
    const u = req.user;
    res.json({ id: u.id, email: u.email, name: u.name, role: u.role, avatarUrl: u.avatar_url });
  } catch (e) { next(e); }
}

async function googleCallback(req, res, next) {
  try {
    const tokens = await svc.issueTokens(req.user);
    const otc    = await svc.storeOtc(tokens.accessToken, tokens.refreshToken);
    logSecurityEvent('oauth.google.success', { userId: req.user.id });
    const config = require('../config');
    res.redirect(`${config.google.appDeepLink}?code=${otc}`);
  } catch (e) { next(e); }
}

async function googleExchange(req, res, next) {
  try {
    const { code } = req.query;
    const { accessToken, refreshToken } = await svc.exchangeOtc(code);
    res.cookie('refresh_token', refreshToken, svc.cookieOpts());
    res.json({ accessToken });
  } catch (e) { next(e); }
}

const verifyOtpSchema = z.object({
  email: z.string().email(),
  otp:   z.string().length(6).regex(/^\d{6}$/),
});

async function verifyEmailOtp(req, res, next) {
  try {
    const { email, otp } = verifyOtpSchema.parse(req.body);
    await svc.verifyEmailOtp(email, otp);
    res.json({ message: 'Email đã được xác thực thành công. Bạn có thể đăng nhập ngay.' });
  } catch (e) { next(e); }
}

const resendSchema = z.object({ email: z.string().email() });

async function resendVerifyEmail(req, res, next) {
  try {
    const { email } = resendSchema.parse(req.body);
    await svc.resendVerifyEmail(email);
    res.json({ message: 'Nếu email tồn tại và chưa xác thực, mã OTP mới đã được gửi.' });
  } catch (e) { next(e); }
}

module.exports = { register, login, refresh, logout, logoutAll, me, forgotPassword, resetPassword, verifyEmailOtp, resendVerifyEmail, googleCallback, googleExchange };
