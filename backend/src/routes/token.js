'use strict';

const express  = require('express');
const { z }    = require('zod');
const { RtcTokenBuilder, RtcRole } = require('agora-token');
const supabase = require('../lib/supabase');
const { authenticate } = require('../middleware/auth');
const { NotFoundError, ValidationError } = require('../errors/AppError');
const config   = require('../config');
const router   = express.Router();

const tokenSchema = z.object({
  sessionId:   z.string().uuid().optional(),
  channelName: z.string().min(1).max(64).optional(),
  uid:         z.number().int().min(0).default(0),
  role:        z.enum(['publisher', 'subscriber']).default('subscriber'),
});

// POST /api/token/agora
router.post('/agora', authenticate, async (req, res, next) => {
  try {
    const body = tokenSchema.parse(req.body);
    let { sessionId, channelName, uid, role } = body;

    // RBAC: only sellers can request publisher tokens
    if (role === 'publisher' && req.user.role !== 'seller' && req.user.role !== 'admin') {
      role = 'subscriber';
    }

    if (!channelName && sessionId) {
      const { data, error } = await supabase
        .from('live_sessions')
        .select('agora_channel')
        .eq('id', sessionId)
        .single();
      if (error || !data) return next(new NotFoundError('Session not found'));
      channelName = data.agora_channel;
    }

    if (!channelName) return next(new ValidationError('channelName or sessionId required'));

    const { appId, appCert } = config.agora;
    if (!appId || !appCert) {
      return res.status(500).json({ error: 'Agora credentials not configured' });
    }

    const agoraRole = role === 'publisher' ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER;
    const expiresAt = Math.floor(Date.now() / 1000) + 3600;
    const token     = RtcTokenBuilder.buildTokenWithUid(appId, appCert, channelName, uid, agoraRole, expiresAt);

    res.json({ token, appId, channel: channelName, uid, expiresIn: 3600 });
  } catch (e) { next(e); }
});

module.exports = router;
