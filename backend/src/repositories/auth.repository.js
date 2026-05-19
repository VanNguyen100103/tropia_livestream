'use strict';

const crypto   = require('crypto');
const { v4: uuidv4 } = require('uuid');
const supabase = require('../lib/supabase');

const REFRESH_TTL_DAYS = 7;

async function findProfileByEmail(email) {
  const { data } = await supabase
    .from('profiles')
    .select('id,email,name,role,avatar_url,password_hash,failed_login_attempts,locked_until,status,email_verified')
    .eq('email', email)
    .maybeSingle();
  return data;
}

async function findProfileById(id) {
  const { data } = await supabase
    .from('profiles')
    .select('id,email,name,role,avatar_url')
    .eq('id', id)
    .single();
  return data;
}

async function emailExists(email) {
  const { data } = await supabase
    .from('profiles')
    .select('id')
    .eq('email', email)
    .maybeSingle();
  return !!data;
}

async function createProfile({ email, passwordHash, fullName, phone, shopName, role }) {
  const { data, error } = await supabase
    .from('profiles')
    .insert({
      email,
      password_hash: passwordHash,
      name:          fullName,
      phone:         phone || null,
      shop_name:     shopName || null,
      role,
    })
    .select('id,email,name,role,avatar_url,created_at')
    .single();
  if (error) throw error;
  return data;
}

async function updateLoginFailure(userId, attempts, lockUntil) {
  const update = { failed_login_attempts: attempts };
  if (lockUntil) update.locked_until = lockUntil;
  await supabase.from('profiles').update(update).eq('id', userId);
}

async function clearLoginFailure(userId) {
  await supabase.from('profiles')
    .update({ failed_login_attempts: 0, locked_until: null })
    .eq('id', userId);
}

async function findRefreshToken(tokenHash) {
  const { data } = await supabase
    .from('refresh_tokens')
    .select('*')
    .eq('token_hash', tokenHash)
    .maybeSingle();
  return data;
}

async function revokeTokenFamily(family) {
  await supabase.from('refresh_tokens').update({ revoked: true }).eq('family', family);
}

async function revokeTokenByHash(tokenHash) {
  await supabase.from('refresh_tokens').update({ revoked: true }).eq('token_hash', tokenHash);
}

async function revokeAllUserTokens(userId) {
  await supabase.from('refresh_tokens').update({ revoked: true }).eq('user_id', userId);
}

async function insertRefreshToken(userId, tokenHash, family, expiresAt) {
  await supabase.from('refresh_tokens').insert({
    user_id:    userId,
    token_hash: tokenHash,
    family,
    expires_at: expiresAt,
  });
}

function makeTokenPair() {
  const rawRefresh = crypto.randomBytes(48).toString('hex');
  const tokenHash  = crypto.createHash('sha256').update(rawRefresh).digest('hex');
  const expiresAt  = new Date(Date.now() + REFRESH_TTL_DAYS * 86_400_000).toISOString();
  return { rawRefresh, tokenHash, expiresAt, family: uuidv4() };
}

async function setPasswordResetToken(userId, tokenHash, expiresAt) {
  await supabase.from('profiles').update({
    password_reset_token:   tokenHash,
    password_reset_expires: expiresAt,
  }).eq('id', userId);
}

async function findProfileByResetToken(tokenHash) {
  const { data } = await supabase
    .from('profiles')
    .select('id,email,name,role,avatar_url,password_reset_expires')
    .eq('password_reset_token', tokenHash)
    .maybeSingle();
  return data;
}

async function clearPasswordResetToken(userId, newPasswordHash) {
  await supabase.from('profiles').update({
    password_hash:          newPasswordHash,
    password_reset_token:   null,
    password_reset_expires: null,
    failed_login_attempts:  0,
    locked_until:           null,
  }).eq('id', userId);
}

async function setVerifyToken(userId, tokenHash, expiresAt) {
  await supabase.from('profiles').update({
    verify_token:         tokenHash,
    verify_token_expires: expiresAt,
  }).eq('id', userId);
}

async function findProfileByVerifyToken(tokenHash) {
  const { data } = await supabase
    .from('profiles')
    .select('id,email,name,email_verified,verify_token_expires')
    .eq('verify_token', tokenHash)
    .maybeSingle();
  return data;
}

async function markEmailVerified(userId) {
  await supabase.from('profiles').update({
    email_verified:       true,
    verify_token:         null,
    verify_token_expires: null,
  }).eq('id', userId);
}

module.exports = {
  findProfileByEmail,
  findProfileById,
  emailExists,
  createProfile,
  updateLoginFailure,
  clearLoginFailure,
  findRefreshToken,
  revokeTokenFamily,
  revokeTokenByHash,
  revokeAllUserTokens,
  insertRefreshToken,
  makeTokenPair,
  setPasswordResetToken,
  findProfileByResetToken,
  clearPasswordResetToken,
  setVerifyToken,
  findProfileByVerifyToken,
  markEmailVerified,
  REFRESH_TTL_DAYS,
};
