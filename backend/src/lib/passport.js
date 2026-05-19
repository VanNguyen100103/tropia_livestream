'use strict';

const passport      = require('passport');
const GoogleStrategy = require('passport-google-oauth20').Strategy;
const crypto        = require('crypto');
const { v4: uuidv4 } = require('uuid');
const supabase      = require('./supabase');
const cfg           = require('../config');
const logger        = require('./logger');

passport.use(new GoogleStrategy(
  {
    clientID:     cfg.google.clientId,
    clientSecret: cfg.google.clientSecret,
    callbackURL:  cfg.google.callbackUrl,
    scope: ['profile', 'email'],
  },
  async (_accessToken, _refreshToken, profile, done) => {
    try {
      const email     = profile.emails?.[0]?.value?.toLowerCase();
      const name      = profile.displayName || profile.name?.givenName || 'Người dùng';
      const avatarUrl = profile.photos?.[0]?.value || null;
      const googleId  = profile.id;

      if (!email) return done(new Error('Google account has no email'));

      // 1. Tìm user đã tồn tại theo email
      const { data: existing } = await supabase
        .from('profiles')
        .select('id,email,name,role,avatar_url,status')
        .eq('email', email)
        .maybeSingle();

      if (existing) {
        if (existing.status === 'deleted') return done(new Error('Account deleted'));

        // Cập nhật google_id + avatar nếu chưa có
        await supabase.from('profiles').update({
          google_id:  googleId,
          avatar_url: existing.avatar_url || avatarUrl,
        }).eq('id', existing.id);

        return done(null, existing);
      }

      // 2. Tạo mới user (không có password_hash — login qua Google only)
      const { data: created, error } = await supabase
        .from('profiles')
        .insert({
          email,
          name,
          avatar_url:  avatarUrl,
          google_id:   googleId,
          role:        'buyer',
          // password_hash để NULL → user này chỉ login được qua Google
        })
        .select('id,email,name,role,avatar_url')
        .single();

      if (error) return done(error);

      logger.info({ email }, 'New user via Google OAuth');
      return done(null, created);
    } catch (err) {
      return done(err);
    }
  },
));

// Passport không dùng session — chỉ dùng JWT sau callback
passport.serializeUser((user, done) => done(null, user));
passport.deserializeUser((user, done) => done(null, user));

module.exports = passport;
