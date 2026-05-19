'use strict';

jest.mock('../../src/repositories/order.repository');
jest.mock('../../src/lib/rabbitmq',  () => ({ publish: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../src/middleware/security', () => ({ logSecurityEvent: jest.fn() }));
jest.mock('../../src/lib/logger',    () => ({ info: jest.fn(), warn: jest.fn(), error: jest.fn() }));
// Mock HTTP helper _post – payment service gọi external gateway
jest.mock('https', () => ({ request: jest.fn() }));
jest.mock('http',  () => ({ request: jest.fn() }));

const crypto  = require('crypto');
const repo    = require('../../src/repositories/order.repository');
const { publish } = require('../../src/lib/rabbitmq');
const { logSecurityEvent } = require('../../src/middleware/security');

// Config test – phải set trước khi require service
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

const svc = require('../../src/services/payment.service');
const { PaymentError, NotFoundError } = require('../../src/errors/AppError');

// ── Fixtures ──────────────────────────────────────────────────────────────────

function makeOrder(overrides = {}) {
  return {
    id: 'order-001', buyer_id: 'user-001', buyer_name: 'Nguyen A',
    total_price: 96_000, status: 'confirmed', payment_status: 'pending',
    ...overrides,
  };
}

// ── getOrderForPayment (shared guard) ─────────────────────────────────────────

describe('payment – getOrderForPayment guard', () => {
  beforeEach(() => jest.clearAllMocks());

  it('throw NotFoundError khi order không tồn tại', async () => {
    repo.findOrderById.mockResolvedValue(null);
    await expect(svc.createMomoPayment('ghost-order', 'user-001'))
      .rejects.toBeInstanceOf(NotFoundError);
  });

  it('throw NotFoundError (BOLA) khi buyer_id không khớp', async () => {
    repo.findOrderById.mockResolvedValue(makeOrder({ buyer_id: 'other-user' }));
    await expect(svc.createMomoPayment('order-001', 'user-001'))
      .rejects.toBeInstanceOf(NotFoundError);
    expect(logSecurityEvent).toHaveBeenCalledWith('payment.bola', expect.any(Object));
  });

  it('throw PaymentError khi order đã thanh toán', async () => {
    repo.findOrderById.mockResolvedValue(makeOrder({ payment_status: 'paid' }));
    await expect(svc.createMomoPayment('order-001', 'user-001'))
      .rejects.toBeInstanceOf(PaymentError);
  });
});

// ── markPaidAndNotify ─────────────────────────────────────────────────────────

describe('payment – markPaidAndNotify', () => {
  beforeEach(() => jest.clearAllMocks());

  it('gọi updateOrderPayment với đúng fields', async () => {
    repo.updateOrderPayment.mockResolvedValue(undefined);
    repo.findOrderById.mockResolvedValue(makeOrder());

    // Trigger qua handleMomoIpn (gọi markPaidAndNotify bên trong)
    const cfg = require('../../src/config').momo;
    // extraData phải là base64(JSON) chứa orderId (như MoMo thực tế gửi)
    const extraData = Buffer.from(JSON.stringify({ orderId: 'order-001' })).toString('base64');
    const body = {
      partnerCode: cfg.partnerCode, requestId: 'req-001', orderId: 'momo-001',
      orderInfo: 'test', orderType: 'momo_wallet', amount: 96_000,
      transId: '4746143698', message: 'Successful.', payType: 'qr',
      responseTime: Date.now(), resultCode: 0, extraData,
    };
    // Tính signature đúng
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

    await svc.handleMomoIpn(body);

    expect(repo.updateOrderPayment).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({ paymentStatus: 'paid', paymentMethod: 'MoMo' })
    );
  });

  it('publish payment.success sau khi mark paid', async () => {
    repo.updateOrderPayment.mockResolvedValue(undefined);
    repo.findOrderById.mockResolvedValue(makeOrder());

    const cfg = require('../../src/config').momo;
    const extraData = Buffer.from(JSON.stringify({ orderId: 'order-001' })).toString('base64');
    const body = {
      partnerCode: cfg.partnerCode, requestId: 'req-002', orderId: 'momo-002',
      orderInfo: 'test', orderType: 'momo_wallet', amount: 96_000,
      transId: '111', message: 'Successful.', payType: 'qr',
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

    await svc.handleMomoIpn(body);
    expect(publish).toHaveBeenCalledWith('payment.success', expect.objectContaining({
      method: 'MoMo',
    }));
  });
});

// ── MoMo IPN signature validation ────────────────────────────────────────────

describe('payment – handleMomoIpn', () => {
  beforeEach(() => jest.clearAllMocks());

  it('throw PaymentError khi signature không hợp lệ', async () => {
    const body = {
      partnerCode: 'MOMO', requestId: 'r', orderId: 'o',
      orderInfo: 'i', orderType: 'momo_wallet', amount: 1000,
      transId: 't', message: 'm', payType: 'qr',
      responseTime: 1, resultCode: 0, extraData: '',
      signature: 'INVALID_SIG',
    };

    await expect(svc.handleMomoIpn(body)).rejects.toBeInstanceOf(PaymentError);
    expect(repo.updateOrderPayment).not.toHaveBeenCalled();
  });

  it('không gọi markPaid khi resultCode != 0', async () => {
    const cfg = require('../../src/config').momo;
    const body = {
      partnerCode: cfg.partnerCode, requestId: 'r', orderId: 'o',
      orderInfo: 'i', orderType: 'momo_wallet', amount: 1000,
      transId: 't', message: 'fail', payType: 'qr',
      responseTime: 1, resultCode: 9000, extraData: '',
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

    await svc.handleMomoIpn(body);
    expect(repo.updateOrderPayment).not.toHaveBeenCalled();
  });
});

// ── ZaloPay callback MAC validation ──────────────────────────────────────────

describe('payment – handleZaloCallback', () => {
  beforeEach(() => jest.clearAllMocks());

  it('throw PaymentError khi MAC không hợp lệ', async () => {
    await expect(svc.handleZaloCallback({ data: '{}', mac: 'INVALID' }))
      .rejects.toBeInstanceOf(PaymentError);
    expect(repo.updateOrderPayment).not.toHaveBeenCalled();
  });

  it('gọi markPaid khi MAC đúng', async () => {
    const cfg = require('../../src/config').zalopay;
    const embedData = JSON.stringify({ orderId: 'order-001', redirecturl: '' });
    const data = JSON.stringify({ zp_trans_id: '123456', embed_data: embedData });
    const mac  = crypto.createHmac('sha256', cfg.key2).update(data).digest('hex');

    repo.updateOrderPayment.mockResolvedValue(undefined);
    repo.findOrderById.mockResolvedValue(makeOrder());

    await svc.handleZaloCallback({ data, mac });
    expect(repo.updateOrderPayment).toHaveBeenCalledWith(
      'order-001',
      expect.objectContaining({ paymentMethod: 'ZaloPay', paymentStatus: 'paid' })
    );
  });
});

// ── VNPay return signature validation ─────────────────────────────────────────

describe('payment – handleVnpayReturn', () => {
  beforeEach(() => jest.clearAllMocks());

  it('throw PaymentError khi signature sai', async () => {
    await expect(svc.handleVnpayReturn({
      vnp_ResponseCode: '00',
      vnp_OrderInfo:    'Thanh toan don hang order-001',
      vnp_TransactionNo: '12345',
      vnp_SecureHash:    'BADSIG',
    })).rejects.toBeInstanceOf(PaymentError);
  });

  it('trả về isPaid=false khi vnp_ResponseCode != 00', async () => {
    const cfg = require('../../src/config').vnpay;
    const params = {
      vnp_ResponseCode:  '24',
      vnp_OrderInfo:     'Thanh toan don hang order-001',
      vnp_TransactionNo: '999',
    };
    const sorted   = Object.keys(params).sort().reduce((a, k) => { a[k] = params[k]; return a; }, {});
    const signData = Object.entries(sorted).map(([k, v]) => `${k}=${v}`).join('&');
    const hash     = crypto.createHmac('sha512', cfg.hashSecret)
                       .update(Buffer.from(signData, 'utf-8')).digest('hex');

    const result = await svc.handleVnpayReturn({ ...params, vnp_SecureHash: hash });
    expect(result.isPaid).toBe(false);
    expect(repo.updateOrderPayment).not.toHaveBeenCalled();
  });
});
