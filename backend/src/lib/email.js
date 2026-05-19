'use strict';

const nodemailer = require('nodemailer');
const cfg        = require('../config').email;

let _transporter = null;

function getTransporter() {
  if (!_transporter) {
    _transporter = nodemailer.createTransport({
      host:   cfg.host,
      port:   cfg.port,
      secure: cfg.secure,
      auth: {
        user: cfg.username,
        pass: cfg.password,
      },
    });
  }
  return _transporter;
}

/**
 * Gửi email HTML.
 * @param {object} opts
 * @param {string}   opts.to
 * @param {string}   opts.subject
 * @param {string}   opts.html
 * @param {string}  [opts.text]   - plain-text fallback
 */
async function sendMail({ to, subject, html, text }) {
  const info = await getTransporter().sendMail({
    from:    `"${cfg.fromName}" <${cfg.username}>`,
    to,
    subject,
    html,
    text: text || html.replace(/<[^>]*>/g, ''),
  });
  return info;
}

// ── Template helpers ─────────────────────────────────────────────────────────

function tplWelcome({ name }) {
  return {
    subject: 'Chào mừng bạn đến với Tropia!',
    html: `
      <h2>Xin chào ${name}!</h2>
      <p>Cảm ơn bạn đã đăng ký tài khoản Tropia.</p>
      <p>Trải nghiệm mua sắm livestream nông sản tươi ngon nhất Việt Nam ngay hôm nay.</p>
      <br>
      <p>Trân trọng,<br><strong>Đội ngũ Tropia</strong></p>
    `,
  };
}

function tplOrderConfirm({ buyerName, productName, quantity, totalPrice, sessionTitle }) {
  return {
    subject: `Xác nhận đơn hàng – ${productName}`,
    html: `
      <h2>Xác nhận đơn hàng</h2>
      <p>Xin chào <strong>${buyerName}</strong>,</p>
      <p>Đơn hàng của bạn đã được đặt thành công trong buổi live <strong>${sessionTitle}</strong>.</p>
      <table>
        <tr><td><b>Sản phẩm</b></td><td>${productName}</td></tr>
        <tr><td><b>Số lượng</b></td><td>${quantity}</td></tr>
        <tr><td><b>Tổng tiền</b></td><td>${Number(totalPrice).toLocaleString('vi-VN')}₫</td></tr>
      </table>
      <br>
      <p>Trân trọng,<br><strong>Đội ngũ Tropia</strong></p>
    `,
  };
}

function tplPasswordReset({ name, resetUrl }) {
  return {
    subject: 'Đặt lại mật khẩu Tropia',
    html: `
      <h2>Đặt lại mật khẩu</h2>
      <p>Xin chào ${name},</p>
      <p>Nhấn vào liên kết bên dưới để đặt lại mật khẩu của bạn (có hiệu lực trong 15 phút):</p>
      <p><a href="${resetUrl}" style="background:#4CAF50;color:white;padding:10px 20px;text-decoration:none;border-radius:4px;">Đặt lại mật khẩu</a></p>
      <p>Nếu bạn không yêu cầu, hãy bỏ qua email này.</p>
      <br>
      <p>Trân trọng,<br><strong>Đội ngũ Tropia</strong></p>
    `,
  };
}

function tplEmailOtp({ name, otp }) {
  return {
    subject: 'Mã xác thực OTP – Tropia',
    html: `
      <div style="font-family:sans-serif;max-width:480px;margin:0 auto">
        <h2 style="color:#2E7D32">Xác thực tài khoản Tropia</h2>
        <p>Xin chào <strong>${name}</strong>,</p>
        <p>Nhập mã OTP sau vào ứng dụng để kích hoạt tài khoản của bạn:</p>
        <p style="text-align:center;margin:32px 0">
          <span style="display:inline-block;background:#f5f5f5;border:2px dashed #4CAF50;border-radius:12px;padding:16px 40px;font-size:36px;font-weight:900;letter-spacing:10px;color:#2E7D32">${otp}</span>
        </p>
        <p style="color:#888;font-size:13px">Mã có hiệu lực trong <strong>10 phút</strong>. Không chia sẻ mã này với ai.</p>
        <p>Nếu bạn không đăng ký tài khoản Tropia, hãy bỏ qua email này.</p>
        <br>
        <p>Trân trọng,<br><strong>Đội ngũ Tropia</strong></p>
      </div>
    `,
  };
}

/**
 * @param {object} opts
 * @param {string}   opts.buyerName
 * @param {string}   opts.orderId
 * @param {string}   opts.method        - MoMo | ZaloPay | VNPay
 * @param {string}   opts.transId
 * @param {number}   opts.amount        - grand total (đã giảm giá)
 * @param {number}   opts.subtotal      - tổng trước giảm
 * @param {number}   opts.discountAmount
 * @param {Array}    opts.items         - [{ name, quantity, unitPrice }]
 * @param {string}   opts.paidAt        - ISO date string
 */
function tplPaymentSuccess({ buyerName, orderId, method, transId, amount, subtotal, discountAmount, items, paidAt }) {
  const fmt  = n => Number(n || 0).toLocaleString('vi-VN') + ' đ';
  const date = paidAt ? new Date(paidAt).toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' }) : '';

  const itemRows = (items || []).map(item => `
    <tr>
      <td style="padding:10px 12px;border-bottom:1px solid #f0f0f0;color:#333">${item.name}</td>
      <td style="padding:10px 12px;border-bottom:1px solid #f0f0f0;text-align:center;color:#333">${item.quantity}</td>
      <td style="padding:10px 12px;border-bottom:1px solid #f0f0f0;text-align:right;color:#333">${fmt(item.unitPrice)}</td>
      <td style="padding:10px 12px;border-bottom:1px solid #f0f0f0;text-align:right;font-weight:600;color:#333">${fmt(item.unitPrice * item.quantity)}</td>
    </tr>`).join('');

  const discountRow = discountAmount > 0 ? `
    <tr>
      <td colspan="3" style="padding:8px 12px;text-align:right;color:#555">Giảm giá voucher</td>
      <td style="padding:8px 12px;text-align:right;color:#2E7D32;font-weight:600">-${fmt(discountAmount)}</td>
    </tr>` : '';

  return {
    subject: `${method} – Thanh toán thành công`,
    html: `
<!DOCTYPE html>
<html lang="vi">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f5f5f5;font-family:'Segoe UI',Arial,sans-serif">
  <div style="max-width:600px;margin:32px auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08)">

    <!-- Header -->
    <div style="background:linear-gradient(135deg,#2E7D32,#43A047);padding:32px 24px;text-align:center">
      <div style="width:64px;height:64px;background:rgba(255,255,255,0.2);border-radius:50%;margin:0 auto 16px;display:flex;align-items:center;justify-content:center">
        <span style="font-size:32px">✓</span>
      </div>
      <h1 style="color:#fff;margin:0;font-size:24px;font-weight:700">Thanh toán thành công!</h1>
      <p style="color:rgba(255,255,255,0.85);margin:8px 0 0;font-size:14px">${date}</p>
    </div>

    <!-- Body -->
    <div style="padding:28px 24px">
      <p style="margin:0 0 20px;color:#444;font-size:15px">Xin chào <strong>${buyerName}</strong>,</p>
      <p style="margin:0 0 24px;color:#444;font-size:14px">
        Đơn hàng <strong style="color:#2E7D32">${orderId}</strong> đã được thanh toán thành công qua <strong>${method}</strong>.
      </p>

      <!-- Transaction info -->
      <table style="width:100%;border-collapse:collapse;margin-bottom:24px;background:#f9f9f9;border-radius:8px;overflow:hidden">
        <tr>
          <td style="padding:10px 16px;color:#666;font-size:13px;width:40%">Mã giao dịch</td>
          <td style="padding:10px 16px;color:#333;font-weight:600;font-size:13px">${transId}</td>
        </tr>
        <tr style="background:#f1f1f1">
          <td style="padding:10px 16px;color:#666;font-size:13px">Phương thức</td>
          <td style="padding:10px 16px;color:#333;font-weight:600;font-size:13px">${method}</td>
        </tr>
        ${date ? `<tr>
          <td style="padding:10px 16px;color:#666;font-size:13px">Thời gian</td>
          <td style="padding:10px 16px;color:#333;font-size:13px">${date}</td>
        </tr>` : ''}
      </table>

      <!-- Items table -->
      <h3 style="margin:0 0 12px;color:#333;font-size:15px;font-weight:700">Chi tiết sản phẩm</h3>
      <table style="width:100%;border-collapse:collapse;border:1px solid #eee;border-radius:8px;overflow:hidden;margin-bottom:16px">
        <thead>
          <tr style="background:#f5f5f5">
            <th style="padding:10px 12px;text-align:left;font-size:13px;color:#555;font-weight:600">Sản phẩm</th>
            <th style="padding:10px 12px;text-align:center;font-size:13px;color:#555;font-weight:600">SL</th>
            <th style="padding:10px 12px;text-align:right;font-size:13px;color:#555;font-weight:600">Đơn giá</th>
            <th style="padding:10px 12px;text-align:right;font-size:13px;color:#555;font-weight:600">Thành tiền</th>
          </tr>
        </thead>
        <tbody>
          ${itemRows}
          ${discountRow}
          <tr style="background:#fff8e1">
            <td colspan="3" style="padding:12px;text-align:right;font-weight:700;color:#333;font-size:15px">Tổng thanh toán</td>
            <td style="padding:12px;text-align:right;font-weight:800;color:#E65100;font-size:18px">${fmt(amount)}</td>
          </tr>
        </tbody>
      </table>

      <p style="margin:24px 0 0;color:#888;font-size:13px;text-align:center">
        Cảm ơn bạn đã mua sắm tại <strong style="color:#2E7D32">Tropia</strong>!<br>
        Đơn hàng sẽ được giao trong 1–3 ngày làm việc.
      </p>
    </div>

    <!-- Footer -->
    <div style="background:#f9f9f9;padding:16px 24px;text-align:center;border-top:1px solid #eee">
      <p style="margin:0;font-size:12px;color:#aaa">© 2026 Tropia – Nông sản tươi ngon mỗi ngày</p>
    </div>
  </div>
</body>
</html>`,
  };
}

module.exports = { sendMail, tplWelcome, tplOrderConfirm, tplPasswordReset, tplEmailOtp, tplPaymentSuccess };
