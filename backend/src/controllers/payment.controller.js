'use strict';

const { z }  = require('zod');
const svc    = require('../services/payment.service');
const logger = require('../lib/logger');

const CLIENT_URL = () => process.env.CLIENT_URL || 'http://localhost:3000';

// ── MoMo ─────────────────────────────────────────────────────────────────────

async function initMomo(req, res, next) {
  try {
    const { orderId } = z.object({ orderId: z.string().uuid() }).parse(req.body);
    const result      = await svc.createMomoPayment(orderId, req.user.id);
    res.json(result);
  } catch (e) { next(e); }
}

async function momoCallback(req, res, next) {
  try {
    const { isPaid, orderId } = await svc.handleMomoCallback(req.query);
    res.redirect(`${CLIENT_URL()}/payment/${isPaid ? 'success' : 'failed'}?orderId=${orderId}`);
  } catch (e) { next(e); }
}

// MoMo redirectUrl sau thanh toán → redirect về Flutter
async function momoResult(req, res, next) {
  try {
    const { isPaid, orderId } = await svc.handleMomoCallback(req.query);
    const status = isPaid ? 'success' : 'failed';
    res.redirect(`${CLIENT_URL()}/#/payment-result?status=${status}&orderId=${encodeURIComponent(orderId || '')}&method=momo`);
  } catch (e) {
    res.redirect(`${CLIENT_URL()}/#/payment-result?status=failed&method=momo`);
  }
}

async function momoIpn(req, res, next) {
  try {
    await svc.handleMomoIpn(req.body);
    res.json({ message: 'ok' });
  } catch (e) {
    logger.error({ err: e }, 'MoMo IPN error');
    res.status(400).json({ message: e.message || 'error' });
  }
}

async function checkMomo(req, res, next) {
  try {
    const { momoOrderId } = z.object({ momoOrderId: z.string() }).parse(req.body);
    const result          = await svc.checkMomoTransaction(momoOrderId);
    res.json(result);
  } catch (e) { next(e); }
}

// ── ZaloPay ───────────────────────────────────────────────────────────────────

async function initZalo(req, res, next) {
  try {
    const { orderId } = z.object({ orderId: z.string().uuid() }).parse(req.body);
    const result      = await svc.createZaloPayment(orderId, req.user.id);
    res.json(result);
  } catch (e) { next(e); }
}

async function zaloCallback(req, res) {
  try {
    await svc.handleZaloCallback(req.body);
    res.json({ return_code: 1, return_message: 'success' });
  } catch (e) {
    logger.error({ err: e }, 'ZaloPay callback error');
    res.json({ return_code: 0, return_message: 'fail' });
  }
}

async function checkZalo(req, res, next) {
  try {
    const { appTransId } = z.object({ appTransId: z.string() }).parse(req.body);
    const result         = await svc.checkZaloTransaction(appTransId);
    res.json(result);
  } catch (e) { next(e); }
}

// ── VNPay ─────────────────────────────────────────────────────────────────────

async function initVnpay(req, res, next) {
  try {
    const { orderId, locale } = z.object({
      orderId: z.string().uuid(),
      locale:  z.enum(['vn', 'en']).default('vn'),
    }).parse(req.body);

    const ipAddr = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '127.0.0.1')
      .split(',')[0].trim();

    const result = await svc.createVnpayUrl(orderId, req.user.id, locale, ipAddr);
    res.json(result);
  } catch (e) { next(e); }
}

async function vnpayReturn(req, res, next) {
  try {
    const { isPaid, orderId } = await svc.handleVnpayReturn(req.query);
    res.redirect(`${CLIENT_URL()}/payment/${isPaid ? 'success' : 'failed'}?orderId=${orderId}`);
  } catch (e) {
    res.redirect(`${CLIENT_URL()}/payment/failed?reason=invalid_signature`);
  }
}

// VNPay returnUrl → redirect về Flutter
async function vnpayResult(req, res, next) {
  try {
    const { isPaid, orderId } = await svc.handleVnpayReturn(req.query);
    const status = isPaid ? 'success' : 'failed';
    res.redirect(`${CLIENT_URL()}/#/payment-result?status=${status}&orderId=${encodeURIComponent(orderId || '')}&method=vnpay`);
  } catch (e) {
    res.redirect(`${CLIENT_URL()}/#/payment-result?status=failed&method=vnpay`);
  }
}

module.exports = {
  initMomo, momoCallback, momoResult, momoIpn, checkMomo,
  initZalo, zaloCallback, checkZalo,
  initVnpay, vnpayReturn, vnpayResult,
};
