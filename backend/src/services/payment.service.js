'use strict';

const crypto   = require('crypto');
const https    = require('https');
const http     = require('http');
const { publish }          = require('../lib/rabbitmq');
const { logSecurityEvent } = require('../middleware/security');
const { PaymentError, NotFoundError } = require('../errors/AppError');
const repo   = require('../repositories/order.repository');
const logger = require('../lib/logger');
const config = require('../config');

// ── HTTP helper ───────────────────────────────────────────────────────────────

function _post(urlStr, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const url  = new URL(urlStr);
    const lib  = url.protocol === 'https:' ? https : http;
    const req  = lib.request({
      hostname: url.hostname,
      port:     url.port || (url.protocol === 'https:' ? 443 : 80),
      path:     url.pathname + url.search,
      method:   'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) },
    }, res => {
      let raw = '';
      res.on('data', c => { raw += c; });
      res.on('end', () => { try { resolve(JSON.parse(raw)); } catch { resolve(raw); } });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

// ── Shared ────────────────────────────────────────────────────────────────────

async function getOrderForPayment(orderId, userId) {
  const order = await repo.findOrderById(orderId);
  if (!order) throw new NotFoundError('Order not found');
  if (order.buyer_id !== userId) {
    logSecurityEvent('payment.bola', { userId, orderId });
    throw new NotFoundError('Order not found');
  }
  if (order.payment_status === 'paid') throw new PaymentError('Order already paid');
  return order;
}

async function markPaidAndNotify(orderId, transactionId, method) {
  await repo.updateOrderPayment(orderId, {
    status:        'confirmed',
    paymentStatus: 'paid',
    paymentMethod: method,
    transactionId,
    paidAt:        new Date().toISOString(),
  });

  const order = await repo.findOrderById(orderId);
  if (order) {
    publish('payment.success', {
      orderId,
      buyerId: order.buyer_id,
      method,
      transId: transactionId,
      amount:  order.total_price,
    }).catch(err => logger.warn({ err }, 'Publish payment.success failed'));
  }
}

// ── MoMo ─────────────────────────────────────────────────────────────────────

function _momoSign(raw) {
  return crypto.createHmac('sha256', config.momo.secretKey).update(raw).digest('hex');
}

async function createMomoPayment(orderId, userId) {
  const order     = await getOrderForPayment(orderId, userId);
  const cfg       = config.momo;
  const requestId = cfg.partnerCode + Date.now();
  const amount    = Math.round(order.total_price);
  const extraData = Buffer.from(JSON.stringify({ orderId })).toString('base64');

  const raw = [
    `accessKey=${cfg.accessKey}`, `amount=${amount}`, `extraData=${extraData}`,
    `ipnUrl=${cfg.ipnUrl}`, `orderId=${requestId}`,
    `orderInfo=Thanh toan don hang ${orderId}`,
    `partnerCode=${cfg.partnerCode}`, `redirectUrl=${cfg.redirectUrl}`,
    `requestId=${requestId}`, `requestType=payWithMethod`,
  ].join('&');

  const data = await _post(`${cfg.apiUrl}/v2/gateway/api/create`, {
    partnerCode: cfg.partnerCode, partnerName: 'Tropia', storeId: cfg.partnerCode,
    requestId, amount, orderId: requestId,
    orderInfo: `Thanh toan don hang ${orderId}`,
    redirectUrl: cfg.redirectUrl, ipnUrl: cfg.ipnUrl,
    lang: 'vi', requestType: 'payWithMethod', autoCapture: true,
    extraData, signature: _momoSign(raw),
  });

  if (data.resultCode !== 0) {
    logger.warn({ data }, 'MoMo create failed');
    throw new PaymentError(data.message || 'MoMo payment init failed');
  }
  logSecurityEvent('payment.momo.initiated', { userId, orderId, amount });
  return { payUrl: data.payUrl, deeplink: data.deeplink };
}

async function handleMomoCallback(query) {
  const { resultCode, extraData, transId } = query;
  const parsed  = JSON.parse(Buffer.from(extraData, 'base64').toString('utf8'));
  const isPaid  = String(resultCode) === '0';
  if (isPaid) await markPaidAndNotify(parsed.orderId, String(transId), 'MoMo');
  return { isPaid, orderId: parsed.orderId };
}

async function handleMomoIpn(body) {
  const cfg = config.momo;
  const raw = [
    `accessKey=${cfg.accessKey}`, `amount=${body.amount}`, `extraData=${body.extraData}`,
    `message=${body.message}`, `orderId=${body.orderId}`, `orderInfo=${body.orderInfo}`,
    `orderType=${body.orderType}`, `partnerCode=${body.partnerCode}`, `payType=${body.payType}`,
    `requestId=${body.requestId}`, `responseTime=${body.responseTime}`,
    `resultCode=${body.resultCode}`, `transId=${body.transId}`,
  ].join('&');

  if (_momoSign(raw) !== body.signature) {
    logSecurityEvent('payment.momo.ipn.invalid_sig', { orderId: body.orderId });
    throw new PaymentError('Invalid signature');
  }
  if (String(body.resultCode) === '0') {
    const parsed = JSON.parse(Buffer.from(body.extraData, 'base64').toString('utf8'));
    await markPaidAndNotify(parsed.orderId, String(body.transId), 'MoMo');
  }
}

async function checkMomoTransaction(momoOrderId) {
  const cfg = config.momo;
  const raw = `accessKey=${cfg.accessKey}&orderId=${momoOrderId}&partnerCode=${cfg.partnerCode}&requestId=${momoOrderId}`;
  return _post(`${cfg.apiUrl}/v2/gateway/api/query`, {
    partnerCode: cfg.partnerCode, requestId: momoOrderId, orderId: momoOrderId,
    signature: _momoSign(raw), lang: 'vi',
  });
}

// ── ZaloPay ───────────────────────────────────────────────────────────────────

async function createZaloPayment(orderId, userId) {
  const order   = await getOrderForPayment(orderId, userId);
  const cfg     = config.zalopay;
  const appTime = Date.now();
  const appTransId = `${new Date().toISOString().slice(0,10).replace(/-/g,'')}${orderId.replace(/-/g,'').slice(0,8)}`;
  const embedData  = JSON.stringify({ redirecturl: cfg.redirectUrl, orderId });
  const amount     = Math.round(order.total_price);

  const raw = `${cfg.appId}|${appTransId}|${userId}|${amount}|${appTime}|${embedData}|[]`;
  const mac = crypto.createHmac('sha256', cfg.key1).update(raw).digest('hex');

  const data = await _post(cfg.apiCreate, {
    app_id: parseInt(cfg.appId), app_trans_id: appTransId, app_user: userId,
    app_time: appTime, amount, embed_data: embedData, item: '[]',
    description: `Tropia - Thanh toan don hang ${orderId}`,
    bank_code: '', callback_url: cfg.callbackUrl, mac,
  });

  if (data.return_code !== 1) {
    logger.warn({ data }, 'ZaloPay create failed');
    throw new PaymentError(data.return_message || 'ZaloPay payment init failed');
  }
  logSecurityEvent('payment.zalopay.initiated', { userId, orderId, amount });
  return { orderUrl: data.order_url, appTransId };
}

async function handleZaloCallback(body) {
  const cfg = config.zalopay;
  const expectedMac = crypto.createHmac('sha256', cfg.key2).update(body.data).digest('hex');
  if (expectedMac !== body.mac) {
    logSecurityEvent('payment.zalopay.invalid_mac', {});
    throw new PaymentError('Invalid MAC');
  }
  const parsed    = JSON.parse(body.data);
  const embedData = JSON.parse(parsed.embed_data);
  await markPaidAndNotify(embedData.orderId, String(parsed.zp_trans_id), 'ZaloPay');
}

async function checkZaloTransaction(appTransId) {
  const cfg = config.zalopay;
  const raw = `${cfg.appId}|${appTransId}|${cfg.key1}`;
  const mac = crypto.createHmac('sha256', cfg.key1).update(raw).digest('hex');
  return _post(cfg.apiQuery, { app_id: parseInt(cfg.appId), app_trans_id: appTransId, mac });
}

// ── VNPay ─────────────────────────────────────────────────────────────────────

function _vnpaySign(params) {
  const sorted   = Object.keys(params).sort().reduce((acc, k) => { acc[k] = params[k]; return acc; }, {});
  const signData = Object.entries(sorted).map(([k, v]) => `${k}=${v}`).join('&');
  return crypto.createHmac('sha512', config.vnpay.hashSecret).update(Buffer.from(signData, 'utf-8')).digest('hex');
}

async function createVnpayUrl(orderId, userId, locale, ipAddr) {
  const order  = await getOrderForPayment(orderId, userId);
  const cfg    = config.vnpay;
  process.env.TZ = 'Asia/Ho_Chi_Minh';
  const now    = new Date();
  const pad    = n => String(n).padStart(2, '0');
  const createDate = `${now.getFullYear()}${pad(now.getMonth()+1)}${pad(now.getDate())}${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  const txnRef = `${orderId.replace(/-/g,'').slice(0,8)}_${Date.now()}`;
  const amount = Math.round(order.total_price);

  const params = {
    vnp_Version: '2.1.0', vnp_Command: 'pay', vnp_TmnCode: cfg.tmnCode,
    vnp_Locale: locale, vnp_CurrCode: 'VND', vnp_TxnRef: txnRef,
    vnp_OrderInfo: `Thanh toan don hang ${orderId}`,
    vnp_OrderType: 'other', vnp_Amount: amount * 100,
    vnp_ReturnUrl: cfg.returnUrl, vnp_IpAddr: ipAddr, vnp_CreateDate: createDate,
  };

  const qs = new URLSearchParams(
    Object.entries({ ...params, vnp_SecureHash: _vnpaySign(params) }).map(([k, v]) => [k, String(v)])
  ).toString();

  logSecurityEvent('payment.vnpay.initiated', { userId, orderId, amount });
  return { payUrl: `${cfg.url}?${qs}`, txnRef };
}

async function handleVnpayReturn(query) {
  const { vnp_SecureHash, vnp_SecureHashType, ...params } = query;
  if (_vnpaySign(params) !== vnp_SecureHash) {
    logSecurityEvent('payment.vnpay.invalid_sig', { txnRef: params.vnp_TxnRef });
    throw new PaymentError('Invalid signature');
  }

  const isPaid  = params.vnp_ResponseCode === '00';
  const orderId = params.vnp_OrderInfo?.replace('Thanh toan don hang ', '').trim();

  if (isPaid && orderId) {
    await markPaidAndNotify(orderId, params.vnp_TransactionNo, 'VNPay');
  }
  return { isPaid, orderId, transactionNo: params.vnp_TransactionNo };
}

module.exports = {
  createMomoPayment, handleMomoCallback, handleMomoIpn, checkMomoTransaction,
  createZaloPayment, handleZaloCallback, checkZaloTransaction,
  createVnpayUrl, handleVnpayReturn,
};
