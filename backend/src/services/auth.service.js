'use strict';

const bcrypt   = require('bcryptjs');
const crypto   = require('crypto');
const { signAccessToken } = require('../middleware/auth');
const { getRedis }        = require('../lib/redis');
const { publish }         = require('../lib/rabbitmq');
const { logSecurityEvent } = require('../middleware/security');
const { AuthError, ConflictError } = require('../errors/AppError');
const repo     = require('../repositories/auth.repository');
const shopRepo = require('../repositories/shop.repository');
const logger   = require('../lib/logger');
const config   = require('../config');

const SALT_ROUNDS   = 12;
const MAX_FAILED    = 5;
const LOCK_MS       = 15 * 60 * 1000;
const OTP_TTL_SECS  = 10 * 60; // 10 phút

function _genOtp() {
  return String(crypto.randomInt(100000, 999999));
}

async function register({ email, password, fullName, phone, shopName, role }) {
  const normalEmail = email.toLowerCase().trim();
  if (await repo.emailExists(normalEmail)) throw new ConflictError('Email already registered');

  const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);
  const profile = await repo.createProfile({ email: normalEmail, passwordHash, fullName, phone, shopName, role });

  // Tự động tạo shop nếu là seller
  if (role === 'seller') {
    const name     = shopName?.trim() || `${fullName}'s Shop`;
    // Normalize Unicode (tiếng Việt) → ASCII rồi slugify
    const ascii    = name.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/gi, 'd');
    const prefix   = ascii.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'shop';
    const slug     = `${prefix}-${profile.id.slice(0, 8)}`;
    await shopRepo.createShop({ name, slug, description: `Shop của ${name}`, is_active: true }, profile.id);
  }

  // Generate 6-digit OTP, store in Redis
  const otp = _genOtp();
  const redis = getRedis();
  await redis.setex(`email_otp:${profile.id}`, OTP_TTL_SECS, otp);

  logSecurityEvent('user.registered', { userId: profile.id, role: profile.role });
  // Chỉ gửi OTP khi đăng ký — email chào mừng gửi sau khi verify thành công
  publish('auth.email_otp', { userId: profile.id, email: profile.email, name: profile.name, otp })
    .catch(err => logger.warn({ err }, 'Publish auth.email_otp failed'));

  return profile;
}

async function verifyEmailOtp(email, otp) {
  if (!otp || typeof otp !== 'string' || !/^\d{6}$/.test(otp.trim())) {
    throw new AuthError('Mã OTP không hợp lệ');
  }

  const normalEmail = email.toLowerCase().trim();
  const user = await repo.findProfileByEmail(normalEmail);
  if (!user || user.status === 'deleted') throw new AuthError('Email không tồn tại');
  if (user.email_verified) return; // idempotent

  const redis = getRedis();
  const stored = await redis.get(`email_otp:${user.id}`);
  if (!stored) throw new AuthError('Mã OTP đã hết hạn. Vui lòng yêu cầu mã mới.');
  if (stored !== otp.trim()) throw new AuthError('Mã OTP không đúng');

  await redis.del(`email_otp:${user.id}`);
  await repo.markEmailVerified(user.id);
  logSecurityEvent('email.verified', { userId: user.id });
  // Gửi email chào mừng sau khi xác thực thành công
  publish('user.registered', { email: user.email, name: user.name })
    .catch(err => logger.warn({ err }, 'Publish user.registered failed'));
}

async function login(email, password, ip) {
  const normalEmail = email.toLowerCase();
  const user = await repo.findProfileByEmail(normalEmail);

  if (!user || user.status === 'deleted') {
    logSecurityEvent('login.invalid_email', { ip, email });
    throw new AuthError('Invalid credentials');
  }

  if (!user.email_verified) {
    logSecurityEvent('login.email_not_verified', { userId: user.id });
    throw new AuthError('Email chưa được xác thực. Vui lòng nhập mã OTP đã gửi đến email của bạn.');
  }

  if (user.locked_until && new Date(user.locked_until) > new Date()) {
    const secs = Math.ceil((new Date(user.locked_until) - Date.now()) / 1000);
    logSecurityEvent('login.account_locked', { userId: user.id, remainingSecs: secs });
    throw new AuthError(`Account locked. Try again in ${secs}s`);
  }

  const match = await bcrypt.compare(password, user.password_hash);
  if (!match) {
    const attempts = (user.failed_login_attempts || 0) + 1;
    const lockUntil = attempts >= MAX_FAILED ? new Date(Date.now() + LOCK_MS).toISOString() : null;
    if (lockUntil) logSecurityEvent('login.brute_force_lockout', { userId: user.id, attempts });
    await repo.updateLoginFailure(user.id, attempts, lockUntil);
    throw new AuthError('Invalid credentials');
  }

  await repo.clearLoginFailure(user.id);
  const tokens = await issueTokens(user);
  logSecurityEvent('login.success', { userId: user.id });
  return { tokens, user };
}

async function refresh(rawToken) {
  if (!rawToken) throw new AuthError('No refresh token');

  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
  const stored    = await repo.findRefreshToken(tokenHash);

  if (!stored || stored.revoked || new Date(stored.expires_at) < new Date()) {
    if (stored) {
      await repo.revokeTokenFamily(stored.family);
      logSecurityEvent('refresh.token_reuse_detected', { userId: stored.user_id, family: stored.family });
    }
    throw new AuthError('Refresh token invalid or expired');
  }

  const user = await repo.findProfileById(stored.user_id);
  if (!user) throw new AuthError('User not found');

  await repo.revokeTokenByHash(tokenHash);
  const tokens = await issueTokens(user, stored.family);
  logSecurityEvent('refresh.rotated', { userId: user.id });
  return { tokens, user };
}

async function logout(rawToken) {
  if (!rawToken) return;
  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
  await repo.revokeTokenByHash(tokenHash);
}

async function logoutAll(userId) {
  await repo.revokeAllUserTokens(userId);
  logSecurityEvent('logout.all_sessions', { userId });
}

async function issueTokens(user, family) {
  const { rawRefresh, tokenHash, expiresAt, family: newFamily } = repo.makeTokenPair();
  const usedFamily = family || newFamily;

  await repo.insertRefreshToken(user.id, tokenHash, usedFamily, expiresAt);

  const accessToken = signAccessToken({
    id:       user.id,
    role:     user.role,
    email:    user.email,
    fullName: user.name,
  });

  return { accessToken, refreshToken: rawRefresh };
}

async function exchangeOtc(code) {
  if (!code || typeof code !== 'string') throw new AuthError('Invalid code');
  const redis = getRedis();
  const key   = `oauth:otc:${code}`;
  const raw   = await redis.get(key);
  if (!raw) throw new AuthError('Code expired or already used');
  await redis.del(key);
  return JSON.parse(raw);
}

async function storeOtc(accessToken, refreshToken) {
  const redis = getRedis();
  const otc   = crypto.randomBytes(24).toString('hex');
  await redis.setex(`oauth:otc:${otc}`, 60, JSON.stringify({ accessToken, refreshToken }));
  return otc;
}

const RESET_TTL_MS = 60 * 60 * 1000; // 1 hour

async function forgotPassword(email) {
  const normalEmail = email.toLowerCase().trim();
  const user = await repo.findProfileByEmail(normalEmail);
  // Always resolve to avoid user enumeration
  if (!user || user.status === 'deleted') return;

  const rawToken  = crypto.randomBytes(32).toString('hex');
  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
  const expiresAt = new Date(Date.now() + RESET_TTL_MS).toISOString();

  await repo.setPasswordResetToken(user.id, tokenHash, expiresAt);

  publish('auth.password_reset', { userId: user.id, resetToken: rawToken })
    .catch(err => logger.warn({ err }, 'Publish auth.password_reset failed'));

  logSecurityEvent('password.reset_requested', { userId: user.id });
}

async function resetPassword(rawToken, newPassword) {
  if (!rawToken || typeof rawToken !== 'string') {
    throw new AuthError('Invalid reset token');
  }

  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
  const user = await repo.findProfileByResetToken(tokenHash);

  if (!user) throw new AuthError('Invalid or expired reset token');
  if (!user.password_reset_expires || new Date(user.password_reset_expires) < new Date()) {
    throw new AuthError('Reset token has expired');
  }

  const newHash = await bcrypt.hash(newPassword, SALT_ROUNDS);
  await repo.clearPasswordResetToken(user.id, newHash);
  await repo.revokeAllUserTokens(user.id);

  logSecurityEvent('password.reset_success', { userId: user.id });
}

function cookieOpts() {
  return {
    httpOnly: true,
    secure:   process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    maxAge:   repo.REFRESH_TTL_DAYS * 86_400_000,
    path:     '/api/auth',
  };
}

async function resendVerifyEmail(email) {
  const normalEmail = email.toLowerCase().trim();
  const user = await repo.findProfileByEmail(normalEmail);
  // Always resolve – no user enumeration
  if (!user || user.status === 'deleted' || user.email_verified) return;

  const otp = _genOtp();
  const redis = getRedis();
  await redis.setex(`email_otp:${user.id}`, OTP_TTL_SECS, otp);

  publish('auth.email_otp', { userId: user.id, email: user.email, name: user.name, otp })
    .catch(err => logger.warn({ err }, 'Publish auth.email_otp failed'));

  logSecurityEvent('email.verify_resent', { userId: user.id });
}

module.exports = { register, login, refresh, logout, logoutAll, forgotPassword, resetPassword, verifyEmailOtp, resendVerifyEmail, issueTokens, exchangeOtc, storeOtc, cookieOpts };
