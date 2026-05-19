'use strict';

/**
 * Notification Worker – gửi email cho tất cả sự kiện hệ thống.
 * Chạy: node src/workers/notification.worker.js
 * PM2:  pm2 start src/workers/notification.worker.js --name notification-worker
 */

require('dotenv').config();

const { connect, subscribe } = require('../lib/rabbitmq');
const { sendMail, tplWelcome, tplOrderConfirm, tplPasswordReset, tplEmailOtp, tplPaymentSuccess } = require('../lib/email');
const supabase   = require('../lib/supabase');
const orderRepo  = require('../repositories/order.repository');
const logger     = require('../lib/logger');

async function getProfile(userId) {
  const { data } = await supabase
    .from('profiles').select('email, name').eq('id', userId).single();
  return data;
}

async function start() {
  await connect();

  // user.registered → welcome email
  await subscribe('user.registered', 'notif.user.registered', async ({ email, name }) => {
    await sendMail({ to: email, ...tplWelcome({ name }) });
    logger.info({ email }, 'Welcome email sent');
  });

  // order.created → confirm email
  await subscribe('order.created', 'notif.order.created', async (payload) => {
    const { buyerId, buyerName, productName, quantity, totalPrice, discountAmount, sessionTitle } = payload;
    const profile = await getProfile(buyerId);
    if (!profile?.email) return;
    const tpl = tplOrderConfirm({ buyerName, productName, quantity, totalPrice, discountAmount, sessionTitle });
    await sendMail({ to: profile.email, ...tpl });
    logger.info({ email: profile.email }, 'Order confirm email sent');
  });

  // payment.success → payment email với chi tiết sản phẩm
  await subscribe('payment.success', 'notif.payment.success', async ({ buyerId, orderId, method, transId, amount }) => {
    const profile = await getProfile(buyerId);
    if (!profile?.email) return;

    // Fetch full order để lấy product_name, quantity, unit_price, discount_amount, paid_at
    const order = await orderRepo.findOrderById(orderId);

    // Xây dựng danh sách items từ order (1 order = 1 dòng sản phẩm gộp)
    const items = order ? [{
      name:      order.product_name || 'Sản phẩm',
      quantity:  order.quantity     || 1,
      unitPrice: order.unit_price   || amount,
    }] : [{ name: 'Đơn hàng Tropia', quantity: 1, unitPrice: amount }];

    const subtotal        = order ? order.unit_price  : amount;
    const discountAmount  = order ? (order.discount_amount || 0) : 0;
    const paidAt          = order?.paid_at || new Date().toISOString();

    const tpl = tplPaymentSuccess({
      buyerName: profile.name,
      orderId,
      method,
      transId,
      amount,
      subtotal,
      discountAmount,
      items,
      paidAt,
    });
    await sendMail({ to: profile.email, ...tpl });
    logger.info({ email: profile.email, orderId }, 'Payment email sent');
  });

  // auth.email_otp → OTP verification email (client là Flutter app, không phải web)
  await subscribe('auth.email_otp', 'notif.auth.email_otp', async ({ email, name, otp }) => {
    await sendMail({ to: email, ...tplEmailOtp({ name, otp }) });
    logger.info({ email }, 'OTP email sent');
  });

  // auth.password_reset → reset email (deep link vào Flutter app)
  await subscribe('auth.password_reset', 'notif.auth.password_reset', async ({ userId, resetToken }) => {
    const profile = await getProfile(userId);
    if (!profile?.email) return;
    const base     = process.env.CLIENT_URL || 'http://localhost:3000';
    const resetUrl = `${base}/reset-password?token=${resetToken}`;
    await sendMail({ to: profile.email, ...tplPasswordReset({ name: profile.name, resetUrl }) });
    logger.info({ email: profile.email }, 'Password reset email sent');
  });

  // order.cancelled → cancellation email
  await subscribe('order.cancelled', 'notif.order.cancelled', async ({ buyerId, orderId, reason }) => {
    const profile = await getProfile(buyerId);
    if (!profile?.email) return;
    const html = `
      <h2>Đơn hàng đã bị huỷ</h2>
      <p>Xin chào <strong>${profile.name}</strong>,</p>
      <p>Đơn hàng <strong>${orderId}</strong> đã bị huỷ.</p>
      ${reason ? `<p>Lý do: ${reason}</p>` : ''}
      <p>Nếu bạn đã thanh toán, tiền sẽ được hoàn lại trong 3-5 ngày làm việc.</p>`;
    await sendMail({ to: profile.email, subject: 'Tropia – Đơn hàng đã bị huỷ', html });
    logger.info({ email: profile.email, orderId }, 'Cancellation email sent');
  });

  logger.info('Notification worker ready');
}

start().catch(err => {
  logger.error({ err }, 'Notification worker crashed');
  process.exit(1);
});
