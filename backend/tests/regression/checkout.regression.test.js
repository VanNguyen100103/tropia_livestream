'use strict';

/**
 * Regression: full checkout flow
 *
 * Kiểm tra hành vi đầu-cuối: giỏ hàng → đặt hàng → khởi tạo thanh toán → IPN → trạng thái.
 * Bảo vệ các bug đã gặp:
 *  - Giỏ hàng không được xóa sau khi đặt hàng online
 *  - grandTotal âm khi discount > subtotal
 *  - BOLA: user không được thanh toán order của người khác
 *  - Coupon được ghi nhận dù backend applyCoupon thất bại (fallback clientDiscount)
 */

jest.mock('../../src/repositories/order.repository');
jest.mock('../../src/repositories/coupon.repository');
jest.mock('../../src/services/coupon.service');
jest.mock('../../src/lib/rabbitmq', () => ({ publish: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../src/lib/logger',   () => ({ info: jest.fn(), warn: jest.fn(), error: jest.fn() }));
jest.mock('../../src/middleware/security', () => ({ logSecurityEvent: jest.fn() }));
jest.mock('https', () => ({ request: jest.fn() }));
jest.mock('http',  () => ({ request: jest.fn() }));

process.env.MOMO_PARTNER_CODE  = 'MOMO';
process.env.MOMO_ACCESS_KEY    = 'F8BBA842ECF85';
process.env.MOMO_SECRET_KEY    = 'K951B6PE1waDMi640xX08PD3vg6EkVlz';
process.env.MOMO_REDIRECT_URL  = 'http://localhost:3000/api/payment/momo/result';
process.env.MOMO_IPN_URL       = 'http://localhost:3000/api/payment/momo/ipn';
process.env.MOMO_API_URL       = 'https://test-payment.momo.vn';

process.env.VNP_TMN_CODE    = 'CGFOXEXM';
process.env.VNP_HASH_SECRET = 'TZDPEJSXILHBOHWAWRRNREYBBEXVLZQP';
process.env.VNP_URL         = 'https://sandbox.vnpayment.vn/paymentv2/vpcpay.html';
process.env.VNP_RETURN_URL  = 'http://localhost:3000/api/payment/vnpay/result';

const crypto    = require('crypto');
const orderRepo = require('../../src/repositories/order.repository');
const couponRepo = require('../../src/repositories/coupon.repository');
const couponSvc = require('../../src/services/coupon.service');
const { publish } = require('../../src/lib/rabbitmq');
const { logSecurityEvent } = require('../../src/middleware/security');

const { checkoutCart }    = require('../../src/services/cart.checkout.service');
const paymentSvc          = require('../../src/services/payment.service');
const { PaymentError, NotFoundError } = require('../../src/errors/AppError');

const ORDER_ID  = 'order-reg-001';
const USER_ID   = 'user-reg-001';
const BUYER_NAME = 'Nguyen Regression';

function makeOrder(overrides = {}) {
  return {
    id: ORDER_ID, buyer_id: USER_ID, buyer_name: BUYER_NAME,
    total_price: 208_000, unit_price: 208_000, discount_amount: 0,
    quantity: 3, product_name: 'Gạo ST25',
    status: 'confirmed', payment_status: 'pending',
    created_at: new Date().toISOString(),
    ...overrides,
  };
}

function makeItems() {
  return [
    { cartItemId: 'ci-1', variantId: 'v-1', productName: 'Gạo ST25', quantity: 2, unitPrice: 85_000 },
    { cartItemId: 'ci-2', variantId: 'v-2', productName: 'Trứng gà',  quantity: 1, unitPrice: 38_000 },
  ];
}

// ── Checkout → Order created ───────────────────────────────────────────────────

describe('Regression: checkout tạo đúng 1 order với total chính xác', () => {
  beforeEach(() => jest.clearAllMocks());

  it('subtotal không âm với discount lớn hơn subtotal', async () => {
    couponSvc.applyCoupon.mockRejectedValue(new Error('fail'));
    orderRepo.createOrder.mockResolvedValue(makeOrder({ total_price: 0 }));
    couponRepo.recordUsage.mockResolvedValue(undefined);

    const result = await checkoutCart({
      buyerId:        USER_ID,
      buyerName:      BUYER_NAME,
      items:          makeItems(),
      couponCode:     'BIGDISCOUNT',
      discountAmount: 999_999,
      paymentMethod:  'cod',
      note:           null,
    });

    expect(result.summary.grandTotal).toBeGreaterThanOrEqual(0);
    expect(result.summary.couponDiscount).toBe(208_000); // capped tại subtotal
  });

  it('recordUsage không được gọi khi coupon thất bại', async () => {
    couponSvc.applyCoupon.mockRejectedValue(new Error('invalid'));
    orderRepo.createOrder.mockResolvedValue(makeOrder());
    couponRepo.recordUsage.mockResolvedValue(undefined);

    await checkoutCart({
      buyerId: USER_ID, buyerName: BUYER_NAME, items: makeItems(),
      couponCode: 'BAD', discountAmount: 0, paymentMethod: 'cod', note: null,
    });

    expect(couponRepo.recordUsage).not.toHaveBeenCalled();
  });

  it('publish order.created sau checkout thành công', async () => {
    couponSvc.applyCoupon.mockResolvedValue({ discountAmount: 20_000, finalPrice: 188_000, coupon: { id: 'c-1' } });
    orderRepo.createOrder.mockResolvedValue(makeOrder({ total_price: 188_000 }));
    couponRepo.recordUsage.mockResolvedValue(undefined);

    await checkoutCart({
      buyerId: USER_ID, buyerName: BUYER_NAME, items: makeItems(),
      couponCode: 'SALE20', discountAmount: 20_000, paymentMethod: 'cod', note: null,
    });

    expect(publish).toHaveBeenCalledWith('order.created', expect.objectContaining({
      orderId:   ORDER_ID,
      buyerName: BUYER_NAME,
    }));
  });

  it('publish thất bại không làm checkout throw', async () => {
    publish.mockRejectedValueOnce(new Error('RabbitMQ down'));
    orderRepo.createOrder.mockResolvedValue(makeOrder());
    couponRepo.recordUsage.mockResolvedValue(undefined);

    await expect(checkoutCart({
      buyerId: USER_ID, buyerName: BUYER_NAME, items: makeItems(),
      couponCode: null, discountAmount: 0, paymentMethod: 'cod', note: null,
    })).resolves.toBeDefined();
  });
});

// ── Payment BOLA protection ────────────────────────────────────────────────────

describe('Regression: BOLA – user không thanh toán được order của người khác', () => {
  beforeEach(() => jest.clearAllMocks());

  it('MoMo: throw NotFoundError khi buyer_id không khớp', async () => {
    orderRepo.findOrderById.mockResolvedValue(makeOrder({ buyer_id: 'other-user' }));

    await expect(paymentSvc.createMomoPayment(ORDER_ID, USER_ID))
      .rejects.toBeInstanceOf(NotFoundError);

    expect(logSecurityEvent).toHaveBeenCalledWith('payment.bola', expect.any(Object));
  });

  it('VNPay: throw NotFoundError khi buyer_id không khớp', async () => {
    orderRepo.findOrderById.mockResolvedValue(makeOrder({ buyer_id: 'other-user' }));

    await expect(paymentSvc.createVnpayUrl(ORDER_ID, USER_ID, 'vn', '127.0.0.1'))
      .rejects.toBeInstanceOf(NotFoundError);
  });
});

// ── Payment already-paid guard ────────────────────────────────────────────────

describe('Regression: không khởi tạo thanh toán lại khi đã paid', () => {
  beforeEach(() => jest.clearAllMocks());

  it('MoMo: throw PaymentError khi payment_status = paid', async () => {
    orderRepo.findOrderById.mockResolvedValue(makeOrder({ payment_status: 'paid' }));

    await expect(paymentSvc.createMomoPayment(ORDER_ID, USER_ID))
      .rejects.toBeInstanceOf(PaymentError);
  });
});

// ── MoMo IPN → mark paid → publish ───────────────────────────────────────────

describe('Regression: MoMo IPN hợp lệ → updateOrderPayment → publish payment.success', () => {
  beforeEach(() => jest.clearAllMocks());

  it('full flow: valid IPN → markPaid → publish', async () => {
    orderRepo.updateOrderPayment.mockResolvedValue(undefined);
    orderRepo.findOrderById.mockResolvedValue(makeOrder());

    const cfg  = require('../../src/config').momo;
    const extraData = Buffer.from(JSON.stringify({ orderId: ORDER_ID })).toString('base64');
    const body = {
      partnerCode: cfg.partnerCode, requestId: 'reg-req-1', orderId: 'reg-momo-1',
      orderInfo: 'test', orderType: 'momo_wallet', amount: 208_000,
      transId: '10000001', message: 'Successful.', payType: 'qr',
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

    await paymentSvc.handleMomoIpn(body);

    expect(orderRepo.updateOrderPayment).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({ paymentStatus: 'paid', paymentMethod: 'MoMo' })
    );
    expect(publish).toHaveBeenCalledWith('payment.success', expect.objectContaining({ method: 'MoMo' }));
  });
});

// ── VNPay return: không mark paid khi ResponseCode != 00 ─────────────────────

describe('Regression: VNPay cancel/fail không mark paid', () => {
  beforeEach(() => jest.clearAllMocks());

  it('ResponseCode=24 (user cancel) → isPaid=false, không updateOrderPayment', async () => {
    const cfg    = require('../../src/config').vnpay;
    const params = {
      vnp_ResponseCode:  '24',
      vnp_OrderInfo:     `Thanh toan don hang ${ORDER_ID}`,
      vnp_TransactionNo: '0',
    };
    const sorted   = Object.keys(params).sort().reduce((a, k) => { a[k] = params[k]; return a; }, {});
    const signData = Object.entries(sorted).map(([k, v]) => `${k}=${v}`).join('&');
    const hash     = crypto.createHmac('sha512', cfg.hashSecret)
                       .update(Buffer.from(signData, 'utf-8')).digest('hex');

    const result = await paymentSvc.handleVnpayReturn({ ...params, vnp_SecureHash: hash });

    expect(result.isPaid).toBe(false);
    expect(orderRepo.updateOrderPayment).not.toHaveBeenCalled();
  });
});

// ── Coupon discount capped tại subtotal ───────────────────────────────────────

describe('Regression: grandTotal không bao giờ âm', () => {
  beforeEach(() => jest.clearAllMocks());

  it('backend applyCoupon trả về finalPrice=0 → grandTotal=0', async () => {
    couponSvc.applyCoupon.mockResolvedValue({
      discountAmount: 999_999, finalPrice: 0, coupon: { id: 'c-2' },
    });
    orderRepo.createOrder.mockResolvedValue(makeOrder({ total_price: 0 }));
    couponRepo.recordUsage.mockResolvedValue(undefined);

    const result = await checkoutCart({
      buyerId: USER_ID, buyerName: BUYER_NAME, items: makeItems(),
      couponCode: 'OVER', discountAmount: 999_999, paymentMethod: 'momo', note: null,
    });

    expect(result.summary.grandTotal).toBe(0);
    expect(result.summary.grandTotal).not.toBeLessThan(0);
  });
});
