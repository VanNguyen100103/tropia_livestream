'use strict';

const express  = require('express');
const { z }    = require('zod');
const { AccessToken, RoomServiceClient } = require('livekit-server-sdk');
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

// POST /api/token/livekit  (Flutter gọi endpoint này)
router.post('/livekit', authenticate, async (req, res, next) => {
  try {
    const body = tokenSchema.parse(req.body);
    let { sessionId, channelName, uid, role } = body;

    // RBAC: chỉ seller/admin được publisher token
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

    const { apiKey, apiSecret, host } = config.livekit;
    if (!apiKey || !apiSecret || !host) {
      return res.status(500).json({ error: 'LiveKit credentials not configured' });
    }

    const identity = `${req.user.id}_${uid}`;
    const ttl      = 3600; // 1 giờ

    const at = new AccessToken(apiKey, apiSecret, {
      identity,
      ttl,
    });

    if (role === 'publisher') {
      at.addGrant({
        roomJoin:     true,
        room:         channelName,
        canPublish:   true,
        canSubscribe: true,
      });
    } else {
      at.addGrant({
        roomJoin:     true,
        room:         channelName,
        canPublish:   false,
        canSubscribe: true,
      });
    }

    const token = await at.toJwt();

    res.json({
      token,
      wsUrl:     host,
      room:      channelName,
      identity,
      expiresIn: ttl,
    });
  } catch (e) { next(e); }
});

module.exports = router;
