'use strict';

jest.mock('../../src/lib/supabase', () => require('../mocks/supabase.mock'));
jest.mock('../../src/lib/redis',    () => require('../mocks/redis.mock'));
jest.mock('../../src/lib/rabbitmq', () => ({ publish: jest.fn().mockResolvedValue(undefined), connect: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../src/middleware/security', () => ({
  helmetConfig:     () => (_, __, next) => next(),
  requestId:        () => (_, __, next) => next(),
  sanitizeInput:    () => (_, __, next) => next(),
  requestSizeGuard: () => (_, __, next) => next(),
  auditLog:         () => (_, __, next) => next(),
  logSecurityEvent: jest.fn(),
}));
// Mock HTTPS – payment service gọi external gateway (chỉ mock https để không break Express)
jest.mock('https', () => ({ request: jest.fn() }));

// Set env trước khi require app
process.env.MOMO_PARTNER_CODE  = 'MOMO';
process.env.MOMO_ACCESS_KEY    = 'F8BBA842ECF85';
process.env.MOMO_SECRET_KEY    = 'K951B6PE1waDMi640xX08PD3vg6EkVlz';
process.env.MOMO_REDIRECT_URL  = 'http://localhost:3000/api/payment/momo/result';
process.env.MOMO_IPN_URL       = 'http://localhost:3000/api/payment/momo/ipn';
process.env.MOMO_API_URL       = 'https://test-payment.momo.vn';

process.env.ZALOPAY_APP_ID       = '2553';
process.env.ZALOPAY_KEY1         = 'PcY4iZIKFCIdgZvA6ueMcMHHUbRLYjPL';
process.env.ZALOPAY_KEY2         = 'kLtgPl8HHhfvMuDHPwKfgfsY4Ydm9eIz';
process.env.ZALOPAY_CALLBACK_URL = 'http://localhost:3000/api/payment/zalopay/callback';
process.env.ZALOPAY_REDIRECT_URL = 'http://localhost:3000/payment/zalopay/result';
process.env.ZALOPAY_API_CREATE   = 'https://sb-openapi.zalopay.vn/v2/create';
process.env.ZALOPAY_API_QUERY    = 'https://sb-openapi.zalopay.vn/v2/query';

process.env.VNP_TMN_CODE    = 'CGFOXEXM';
process.env.VNP_HASH_SECRET = 'TZDPEJSXILHBOHWAWRRNREYBBEXVLZQP';
process.env.VNP_URL         = 'https://sandbox.vnpayment.vn/paymentv2/vpcpay.html';
process.env.VNP_RETURN_URL  = 'http://localhost:3000/api/payment/vnpay/result';

const crypto   = require('crypto');
const request  = require('supertest');
const app      = require('../../src/index');
const { bearerHeader } = require('../helpers/token');
const supabaseMock     = require('../mocks/supabase.mock');

const AUTH      = bearerHeader({ id: 'user-001', role: 'buyer' });
const ORDER_UUID = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

function makeOrder(overrides = {}) {
  return {
    id:             ORDER_UUID,
    buyer_id:       'user-001',
    buyer_name:     'Nguyen A',
    total_price:    170_000,
    status:         'confirmed',
    payment_status: 'pending',
    ...overrides,
  };
}

// ── POST /api/payment/momo ────────────────────────────────────────────────────

describe('POST /api/payment/momo', () => {
  beforeEach(() => supabaseMock.__reset());

  it('422 khi thiếu orderId', async () => {
    const res = await request(app)
      .post('/api/payment/momo')
      .set(AUTH)
      .send({});

    expect(res.status).toBe(422);
  });

  it('422 khi orderId không phải UUID', async () => {
    const res = await request(app)
      .post('/api/payment/momo')
      .set(AUTH)
      .send({ orderId: 'not-a-uuid' });

    expect(res.status).toBe(422);
  });

  it('401 khi không có token', async () => {
    const res = await request(app)
      .post('/api/payment/momo')
      .send({ orderId: ORDER_UUID });

    expect(res.status).toBe(401);
  });

  it('404 khi order không tồn tại', async () => {
    supabaseMock.__setSelectResult(null);

    const res = await request(app)
      .post('/api/payment/momo')
      .set(AUTH)
      .send({ orderId: ORDER_UUID });

    expect(res.status).toBe(404);
  });

  it('404 khi buyer_id không khớp (BOLA)', async () => {
    supabaseMock.__setSelectResult(makeOrder({ buyer_id: 'other-user' }));

    const res = await request(app)
      .post('/api/payment/momo')
      .set(AUTH)
      .send({ orderId: ORDER_UUID });

    expect(res.status).toBe(404);
  });

  it('402 khi order đã thanh toán', async () => {
    supabaseMock.__setSelectResult(makeOrder({ payment_status: 'paid' }));

    const res = await request(app)
      .post('/api/payment/momo')
      .set(AUTH)
      .send({ orderId: ORDER_UUID });

    expect(res.status).toBe(402);
  });
});

// ── POST /api/payment/zalopay ─────────────────────────────────────────────────

describe('POST /api/payment/zalopay', () => {
  beforeEach(() => supabaseMock.__reset());

  it('422 khi thiếu orderId', async () => {
    const res = await request(app)
      .post('/api/payment/zalopay')
      .set(AUTH)
      .send({});

    expect(res.status).toBe(422);
  });

  it('401 khi không có token', async () => {
    const res = await request(app)
      .post('/api/payment/zalopay')
      .send({ orderId: ORDER_UUID });

    expect(res.status).toBe(401);
  });

  it('404 khi order không tồn tại', async () => {
    supabaseMock.__setSelectResult(null);

    const res = await request(app)
      .post('/api/payment/zalopay')
      .set(AUTH)
      .send({ orderId: ORDER_UUID });

    expect(res.status).toBe(404);
  });
});

// ── POST /api/payment/vnpay ───────────────────────────────────────────────────

describe('POST /api/payment/vnpay', () => {
  beforeEach(() => supabaseMock.__reset());

  it('422 khi thiếu orderId', async () => {
    const res = await request(app)
      .post('/api/payment/vnpay')
      .set(AUTH)
      .send({});

    expect(res.status).toBe(422);
  });

  it('422 khi locale không hợp lệ', async () => {
    const res = await request(app)
      .post('/api/payment/vnpay')
      .set(AUTH)
      .send({ orderId: ORDER_UUID, locale: 'fr' });

    expect(res.status).toBe(422);
  });

  it('401 khi không có token', async () => {
    const res = await request(app)
      .post('/api/payment/vnpay')
      .send({ orderId: ORDER_UUID });

    expect(res.status).toBe(401);
  });

  it('404 khi order không tồn tại', async () => {
    supabaseMock.__setSelectResult(null);

    const res = await request(app)
      .post('/api/payment/vnpay')
      .set(AUTH)
      .send({ orderId: ORDER_UUID });

    expect(res.status).toBe(404);
  });
});

// ── POST /api/payment/momo/ipn ────────────────────────────────────────────────

describe('POST /api/payment/momo/ipn', () => {
  beforeEach(() => supabaseMock.__reset());

  it('400 khi signature không hợp lệ', async () => {
    const res = await request(app)
      .post('/api/payment/momo/ipn')
      .send({
        partnerCode: 'MOMO', requestId: 'r', orderId: 'o',
        orderInfo: 'i', orderType: 'momo_wallet', amount: 1000,
        transId: 't', message: 'm', payType: 'qr',
        responseTime: 1, resultCode: 0, extraData: '',
        signature: 'INVALID',
      });

    expect(res.status).toBe(400);
  });

  it('200 khi signature đúng và resultCode = 0', async () => {
    const cfg = require('../../src/config').momo;
    const extraData = Buffer.from(JSON.stringify({ orderId: ORDER_UUID })).toString('base64');
    const body = {
      partnerCode: cfg.partnerCode, requestId: 'req-ipn-1', orderId: 'momo-ipn-1',
      orderInfo: 'test', orderType: 'momo_wallet', amount: 170_000,
      transId: '9999001', message: 'Successful.', payType: 'qr',
      responseTime: Date.now(), resultCode: 0, extraData,
    };
    const rawStr = [
      `accessKey=${cfg.accessKey}`, `amount=${body.amount}`,
      `extraData=${body.extraData}`, `message=${body.message}`,
      `orderId=${body.orderId}`, `orderInfo=${body.orderInfo}`,
      `orderType=${body.orderType}`, `partnerCode=${body.partnerCode}`,
      `payType=${body.payType}`, `requestId=${body.requestId}`,
      `responseTime=${body.responseTime}`, `resultCode=${body.resultCode}`,
      `transId=${body.transId}`,
    ].join('&');
    body.signature = crypto.createHmac('sha256', cfg.secretKey).update(rawStr).digest('hex');

    supabaseMock.__setSelectResult(makeOrder());
    supabaseMock.__setUpdateResult(makeOrder({ payment_status: 'paid' }));

    const res = await request(app)
      .post('/api/payment/momo/ipn')
      .send(body);

    expect(res.status).toBe(200);
    expect(res.body.message).toBe('ok');
  });

  it('200 khi signature đúng nhưng resultCode != 0 (payment fail, không update)', async () => {
    const cfg = require('../../src/config').momo;
    const body = {
      partnerCode: cfg.partnerCode, requestId: 'req-ipn-2', orderId: 'momo-ipn-2',
      orderInfo: 'test', orderType: 'momo_wallet', amount: 170_000,
      transId: '9999002', message: 'Failed.', payType: 'qr',
      responseTime: Date.now(), resultCode: 1006, extraData: '',
    };
    const rawStr = [
      `accessKey=${cfg.accessKey}`, `amount=${body.amount}`,
      `extraData=${body.extraData}`, `message=${body.message}`,
      `orderId=${body.orderId}`, `orderInfo=${body.orderInfo}`,
      `orderType=${body.orderType}`, `partnerCode=${body.partnerCode}`,
      `payType=${body.payType}`, `requestId=${body.requestId}`,
      `responseTime=${body.responseTime}`, `resultCode=${body.resultCode}`,
      `transId=${body.transId}`,
    ].join('&');
    body.signature = crypto.createHmac('sha256', cfg.secretKey).update(rawStr).digest('hex');

    const res = await request(app)
      .post('/api/payment/momo/ipn')
      .send(body);

    expect(res.status).toBe(200);
  });
});

// ── POST /api/payment/zalopay/callback ────────────────────────────────────────

describe('POST /api/payment/zalopay/callback', () => {
  beforeEach(() => supabaseMock.__reset());

  it('trả về return_code=0 khi MAC không hợp lệ', async () => {
    const res = await request(app)
      .post('/api/payment/zalopay/callback')
      .send({ data: '{}', mac: 'INVALID' });

    expect(res.body.return_code).toBe(0);
  });

  it('trả về return_code=1 khi MAC đúng', async () => {
    const cfg      = require('../../src/config').zalopay;
    const embedData = JSON.stringify({ orderId: ORDER_UUID, redirecturl: '' });
    const data      = JSON.stringify({ zp_trans_id: '123456', embed_data: embedData });
    const mac       = crypto.createHmac('sha256', cfg.key2).update(data).digest('hex');

    supabaseMock.__setSelectResult(makeOrder());
    supabaseMock.__setUpdateResult(makeOrder({ payment_status: 'paid' }));

    const res = await request(app)
      .post('/api/payment/zalopay/callback')
      .send({ data, mac });

    expect(res.body.return_code).toBe(1);
  });
});

// ── GET /api/payment/vnpay/return ─────────────────────────────────────────────

describe('GET /api/payment/vnpay/return', () => {
  beforeEach(() => supabaseMock.__reset());

  it('302 redirect khi signature sai', async () => {
    const res = await request(app)
      .get('/api/payment/vnpay/return')
      .query({
        vnp_ResponseCode: '00',
        vnp_OrderInfo:    'Thanh toan don hang order-001',
        vnp_TransactionNo: '12345',
        vnp_SecureHash:   'BADSIG',
      });

    expect(res.status).toBe(302);
    expect(res.headers.location).toContain('failed');
  });

  it('302 redirect về success khi chữ ký đúng và ResponseCode=00', async () => {
    const cfg    = require('../../src/config').vnpay;
    const params = {
      vnp_ResponseCode:  '00',
      vnp_OrderInfo:     `Thanh toan don hang ${ORDER_UUID}`,
      vnp_TransactionNo: '7777',
    };
    const sorted   = Object.keys(params).sort().reduce((a, k) => { a[k] = params[k]; return a; }, {});
    const signData = Object.entries(sorted).map(([k, v]) => `${k}=${v}`).join('&');
    const hash     = crypto.createHmac('sha512', cfg.hashSecret)
                       .update(Buffer.from(signData, 'utf-8')).digest('hex');

    supabaseMock.__setSelectResult(makeOrder());
    supabaseMock.__setUpdateResult(makeOrder({ payment_status: 'paid' }));

    const res = await request(app)
      .get('/api/payment/vnpay/return')
      .query({ ...params, vnp_SecureHash: hash });

    expect(res.status).toBe(302);
    expect(res.headers.location).toContain('success');
  });
});
