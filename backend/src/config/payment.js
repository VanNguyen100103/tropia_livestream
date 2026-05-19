'use strict';

module.exports = {
  momo: {
    accessKey:   process.env.MOMO_ACCESS_KEY   || 'F8BBA842ECF85',
    secretKey:   process.env.MOMO_SECRET_KEY   || 'K951B6PE1waDMi640xX08PD3vg6EkVlz',
    partnerCode: process.env.MOMO_PARTNER_CODE || 'MOMO',
    redirectUrl: process.env.MOMO_REDIRECT_URL || 'http://localhost:3000/payment/momo/result',
    ipnUrl:      process.env.MOMO_IPN_URL      || 'http://localhost:3000/api/payment/momo/ipn',
    apiUrl:      process.env.MOMO_API_URL      || 'https://test-payment.momo.vn',
  },

  zalopay: {
    appId:       process.env.ZALOPAY_APP_ID      || '2553',
    key1:        process.env.ZALOPAY_KEY1         || 'PcY4iZIKFCIdgZvA6ueMcMHHUbRLYjPL',
    key2:        process.env.ZALOPAY_KEY2         || 'kLtgPl8HHhfvMuDHPwKfgfsY4Ydm9eIz',
    callbackUrl: process.env.ZALOPAY_CALLBACK_URL || 'http://localhost:3000/api/payment/zalopay/callback',
    redirectUrl: process.env.ZALOPAY_REDIRECT_URL || 'http://localhost:3000/payment/zalopay/result',
    apiCreate:   process.env.ZALOPAY_API_CREATE   || 'https://sb-openapi.zalopay.vn/v2/create',
    apiQuery:    process.env.ZALOPAY_API_QUERY    || 'https://sb-openapi.zalopay.vn/v2/query',
  },

  vnpay: {
    tmnCode:    process.env.VNP_TMN_CODE    || 'CGFOXEXM',
    hashSecret: process.env.VNP_HASH_SECRET || 'TZDPEJSXILHBOHWAWRRNREYBBEXVLZQP',
    url:        process.env.VNP_URL         || 'https://sandbox.vnpayment.vn/paymentv2/vpcpay.html',
    returnUrl:  process.env.VNP_RETURN_URL  || 'http://localhost:3000/api/payment/vnpay/return',
  },
};
