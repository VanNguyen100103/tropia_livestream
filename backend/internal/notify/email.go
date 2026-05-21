package notify

import (
	"crypto/tls"
	"fmt"
	"net/smtp"
	"strings"
	"time"
)

type EmailConfig struct {
	Host     string
	Port     int
	Username string
	Password string
	FromName string
	Secure   bool
}

type Email struct{ cfg EmailConfig }

func NewEmail(cfg EmailConfig) *Email { return &Email{cfg: cfg} }

func (e *Email) Send(to, subject, htmlBody string) error {
	from := fmt.Sprintf("%s <%s>", e.cfg.FromName, e.cfg.Username)
	msg := []byte(
		"From: " + from + "\r\n" +
			"To: " + to + "\r\n" +
			"Subject: " + subject + "\r\n" +
			"MIME-Version: 1.0\r\n" +
			"Content-Type: text/html; charset=UTF-8\r\n\r\n" +
			htmlBody,
	)
	addr := fmt.Sprintf("%s:%d", e.cfg.Host, e.cfg.Port)
	auth := smtp.PlainAuth("", e.cfg.Username, e.cfg.Password, e.cfg.Host)

	if e.cfg.Secure {
		// SMTPS (port 465)
		conn, err := tls.Dial("tcp", addr, &tls.Config{ServerName: e.cfg.Host})
		if err != nil {
			return err
		}
		client, err := smtp.NewClient(conn, e.cfg.Host)
		if err != nil {
			return err
		}
		defer client.Quit()
		if err := client.Auth(auth); err != nil {
			return err
		}
		if err := client.Mail(e.cfg.Username); err != nil {
			return err
		}
		if err := client.Rcpt(to); err != nil {
			return err
		}
		w, err := client.Data()
		if err != nil {
			return err
		}
		if _, err := w.Write(msg); err != nil {
			return err
		}
		return w.Close()
	}
	// STARTTLS (587) - smtp.SendMail handles upgrade
	return smtp.SendMail(addr, auth, e.cfg.Username, []string{to}, msg)
}

// ============================================================================
// Email templates — Tropia brand
// ============================================================================
//
// Brand colors:
//   primary green = #16A34A   (CTA buttons, success states)
//   dark green    = #0D6B33   (headers, footers)
//   accent orange = #EA580C   (totals, sale prices)
//   light bg      = #F6FBF6   (card backgrounds)
//
// Tagline: "Tropia – Nông sản tươi ngon mỗi ngày"
//
// All templates render inline-styled HTML (max email-client compat) inside
// a 600px centered card with rounded corners.

const (
	brandPrimary = "#16A34A"
	brandDark    = "#0D6B33"
	brandAccent  = "#EA580C"
	brandLight   = "#F6FBF6"
	brandBorder  = "#E5E7EB"
	brandMuted   = "#6B7280"
)

// envelope wraps an arbitrary inner HTML fragment in the standard Tropia card.
func envelope(inner string) string {
	year := time.Now().Year()
	return fmt.Sprintf(`<!doctype html>
<html lang="vi">
  <body style="margin:0;padding:24px 12px;background:#F3F4F6;font-family:'Segoe UI',Arial,sans-serif;color:#111;">
    <table role="presentation" cellpadding="0" cellspacing="0" border="0"
           style="max-width:600px;margin:0 auto;background:#FFFFFF;border-radius:12px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.08)">
      <tr><td>%s</td></tr>
      <tr><td style="padding:20px 24px;border-top:1px solid %s;text-align:center;color:%s;font-size:12px;">
        © %d Tropia – Nông sản tươi ngon mỗi ngày
      </td></tr>
    </table>
  </body>
</html>`, inner, brandBorder, brandMuted, year)
}

// ── OTP ─────────────────────────────────────────────────────────────────────

func TmplOTP(name, otp string) (string, string) {
	subject := "Mã xác thực OTP – Tropia"
	body := envelope(fmt.Sprintf(`
		<div style="padding:32px 24px;text-align:center;">
		  <h1 style="margin:0 0 24px 0;color:%s;font-size:22px;font-weight:700;">Xác thực tài khoản Tropia</h1>
		  <p style="margin:0 0 16px 0;font-size:15px;text-align:left;">
		    Xin chào <strong>%s</strong>,
		  </p>
		  <p style="margin:0 0 24px 0;font-size:15px;text-align:left;">
		    Nhập mã OTP sau vào ứng dụng để kích hoạt tài khoản của bạn:
		  </p>
		  <div style="border:2px dashed %s;border-radius:12px;padding:24px;margin:0 0 24px 0;">
		    <div style="font-size:36px;letter-spacing:12px;font-weight:700;color:%s;">%s</div>
		  </div>
		  <p style="margin:0 0 12px 0;color:%s;font-size:13px;">
		    Mã có hiệu lực trong <strong>10 phút</strong>. Không chia sẻ mã này với ai.
		  </p>
		  <p style="margin:24px 0 0 0;color:%s;font-size:13px;text-align:left;">
		    Nếu bạn không đăng ký tài khoản Tropia, hãy bỏ qua email này.
		  </p>
		  <p style="margin:16px 0 0 0;color:%s;font-size:13px;text-align:left;">
		    Trân trọng,<br/><strong>Đội ngũ Tropia</strong>
		  </p>
		</div>`,
		brandDark, name, brandPrimary, brandPrimary, otp, brandMuted, brandMuted, brandMuted))
	return subject, body
}

// ── Welcome ─────────────────────────────────────────────────────────────────

func TmplWelcome(name string) (string, string) {
	subject := "Chào mừng đến với Tropia 🍎"
	body := envelope(fmt.Sprintf(`
		<div style="background:linear-gradient(135deg,%s 0%%,%s 100%%);padding:40px 24px;text-align:center;color:#fff;">
		  <div style="font-size:48px;line-height:1;margin-bottom:8px;">🌿</div>
		  <h1 style="margin:0;font-size:24px;font-weight:700;">Chào mừng đến với Tropia!</h1>
		  <p style="margin:8px 0 0 0;opacity:0.9;font-size:14px;">Nông sản tươi ngon, giao tận nhà</p>
		</div>
		<div style="padding:32px 24px;">
		  <p style="margin:0 0 16px 0;font-size:15px;">Xin chào <strong>%s</strong>,</p>
		  <p style="margin:0 0 16px 0;font-size:15px;line-height:1.6;">
		    Cảm ơn bạn đã tham gia Tropia — nền tảng mua sắm thực phẩm tươi sống kết hợp livestream
		    bán hàng. Khám phá ngay các tính năng:
		  </p>
		  <ul style="margin:0 0 24px 0;padding-left:20px;font-size:15px;line-height:1.8;">
		    <li>🛒 Mua trái cây, rau củ, hải sản tươi mỗi ngày</li>
		    <li>📺 Xem livestream từ các nhà cung cấp uy tín</li>
		    <li>🎁 Voucher độc quyền chỉ có trong buổi live</li>
		    <li>🚚 Giao hàng nhanh trong 1–3 ngày</li>
		  </ul>
		  <p style="margin:16px 0 0 0;color:%s;font-size:13px;">
		    Trân trọng,<br/><strong>Đội ngũ Tropia</strong>
		  </p>
		</div>`, brandPrimary, brandDark, name, brandMuted))
	return subject, body
}

// ── Password reset ──────────────────────────────────────────────────────────

func TmplPasswordReset(name, link string) (string, string) {
	subject := "Đặt lại mật khẩu Tropia"
	body := envelope(fmt.Sprintf(`
		<div style="padding:32px 24px;">
		  <h1 style="margin:0 0 16px 0;color:%s;font-size:22px;font-weight:700;">Đặt lại mật khẩu</h1>
		  <p style="margin:0 0 16px 0;font-size:15px;">Xin chào <strong>%s</strong>,</p>
		  <p style="margin:0 0 24px 0;font-size:15px;line-height:1.6;">
		    Chúng tôi nhận được yêu cầu đặt lại mật khẩu cho tài khoản của bạn.
		    Click nút bên dưới để đặt lại (liên kết có hiệu lực trong <strong>1 giờ</strong>):
		  </p>
		  <div style="text-align:center;margin:0 0 24px 0;">
		    <a href="%s"
		       style="display:inline-block;padding:14px 32px;background:%s;color:#fff;text-decoration:none;border-radius:8px;font-weight:600;font-size:15px;">
		      Đặt lại mật khẩu
		    </a>
		  </div>
		  <p style="margin:0 0 12px 0;color:%s;font-size:13px;">
		    Hoặc copy đường dẫn này vào trình duyệt:
		  </p>
		  <p style="margin:0 0 24px 0;word-break:break-all;color:%s;font-size:12px;background:%s;padding:12px;border-radius:6px;">
		    %s
		  </p>
		  <p style="margin:16px 0 0 0;color:%s;font-size:13px;">
		    Nếu bạn không yêu cầu đặt lại mật khẩu, hãy bỏ qua email này.
		    Mật khẩu hiện tại của bạn vẫn an toàn.
		  </p>
		  <p style="margin:16px 0 0 0;color:%s;font-size:13px;">
		    Trân trọng,<br/><strong>Đội ngũ Tropia</strong>
		  </p>
		</div>`, brandDark, name, link, brandPrimary, brandMuted, brandDark, brandLight, link, brandMuted, brandMuted))
	return subject, body
}

// ── Order confirm ───────────────────────────────────────────────────────────

func TmplOrderConfirm(name, orderID string, total int) (string, string) {
	subject := "Xác nhận đơn hàng – Tropia"
	body := envelope(fmt.Sprintf(`
		<div style="background:%s;padding:32px 24px;text-align:center;color:#fff;">
		  <div style="font-size:48px;line-height:1;margin-bottom:8px;">📦</div>
		  <h1 style="margin:0;font-size:22px;font-weight:700;">Đơn hàng đã được tiếp nhận</h1>
		  <p style="margin:8px 0 0 0;opacity:0.9;font-size:13px;">%s</p>
		</div>
		<div style="padding:32px 24px;">
		  <p style="margin:0 0 16px 0;font-size:15px;">Xin chào <strong>%s</strong>,</p>
		  <p style="margin:0 0 24px 0;font-size:15px;line-height:1.6;">
		    Đơn hàng <span style="color:%s;font-weight:600;">%s</span> đã được Tropia tiếp nhận.
		    Tổng giá trị: <strong style="color:%s;">%s ₫</strong>
		  </p>
		  <p style="margin:0 0 8px 0;font-size:14px;color:%s;">
		    Chúng tôi sẽ xử lý và giao hàng đến bạn trong <strong>1–3 ngày làm việc</strong>.
		  </p>
		  <p style="margin:16px 0 0 0;color:%s;font-size:13px;">
		    Trân trọng,<br/><strong>Đội ngũ Tropia</strong>
		  </p>
		</div>`,
		brandPrimary, time.Now().Format("15:04:05 02/01/2006"),
		name, brandPrimary, orderID, brandAccent, formatVND(total),
		brandMuted, brandMuted))
	return subject, body
}

// ── Payment success ─────────────────────────────────────────────────────────

// PaymentItem is one line on the payment receipt.
type PaymentItem struct {
	Name     string
	Quantity int
	Price    int // VND per item
}

// TmplPaymentSuccess matches the screenshot layout: hero check + transaction
// table + itemized table + (voucher row) + grand total. Pass an empty
// `items` slice if you only want the summary (the table is then omitted).
func TmplPaymentSuccess(in PaymentSuccessInput) (string, string) {
	subject := "Thanh toán thành công – Tropia"

	// Build product rows
	var rowsHTML strings.Builder
	for _, it := range in.Items {
		fmt.Fprintf(&rowsHTML, `
		    <tr>
		      <td style="padding:12px;border-bottom:1px solid %s;">%s</td>
		      <td style="padding:12px;border-bottom:1px solid %s;text-align:center;">%d</td>
		      <td style="padding:12px;border-bottom:1px solid %s;text-align:right;">%s ₫</td>
		      <td style="padding:12px;border-bottom:1px solid %s;text-align:right;font-weight:600;">%s ₫</td>
		    </tr>`,
			brandBorder, escapeHTML(it.Name),
			brandBorder, it.Quantity,
			brandBorder, formatVND(it.Price),
			brandBorder, formatVND(it.Price*it.Quantity))
	}

	// Voucher row (only if discount > 0)
	voucherRow := ""
	if in.DiscountAmount > 0 {
		voucherRow = fmt.Sprintf(`
		    <tr>
		      <td colspan="3" style="padding:12px;text-align:right;color:%s;">Giảm giá voucher</td>
		      <td style="padding:12px;text-align:right;color:%s;font-weight:600;">-%s ₫</td>
		    </tr>`, brandMuted, brandPrimary, formatVND(in.DiscountAmount))
	}

	// Items section
	itemsSection := ""
	if len(in.Items) > 0 {
		itemsSection = fmt.Sprintf(`
		  <h3 style="margin:24px 0 12px 0;font-size:16px;color:%s;">Chi tiết sản phẩm</h3>
		  <table role="presentation" cellpadding="0" cellspacing="0" border="0"
		         style="width:100%%;border-collapse:collapse;font-size:14px;">
		    <tr style="background:%s;color:%s;font-weight:600;">
		      <th align="left"   style="padding:10px 12px;">Sản phẩm</th>
		      <th align="center" style="padding:10px 12px;">SL</th>
		      <th align="right"  style="padding:10px 12px;">Đơn giá</th>
		      <th align="right"  style="padding:10px 12px;">Thành tiền</th>
		    </tr>
		    %s
		    %s
		    <tr style="background:#FFF7ED;">
		      <td colspan="3" style="padding:14px 12px;text-align:right;font-weight:700;">Tổng thanh toán</td>
		      <td style="padding:14px 12px;text-align:right;color:%s;font-size:18px;font-weight:700;">%s ₫</td>
		    </tr>
		  </table>`,
			brandDark, brandLight, brandDark, rowsHTML.String(), voucherRow,
			brandAccent, formatVND(in.TotalPrice))
	}

	body := envelope(fmt.Sprintf(`
		<div style="background:linear-gradient(135deg,%s 0%%,%s 100%%);padding:32px 24px;text-align:center;color:#fff;">
		  <div style="width:56px;height:56px;margin:0 auto 12px auto;border-radius:50%%;background:#FFFFFF;display:flex;align-items:center;justify-content:center;">
		    <span style="color:%s;font-size:32px;font-weight:700;line-height:56px;">✓</span>
		  </div>
		  <h1 style="margin:0;font-size:24px;font-weight:700;">Thanh toán thành công!</h1>
		  <p style="margin:8px 0 0 0;opacity:0.95;font-size:13px;">%s</p>
		</div>
		<div style="padding:32px 24px;">
		  <p style="margin:0 0 16px 0;font-size:15px;">Xin chào <strong>%s</strong>,</p>
		  <p style="margin:0 0 16px 0;font-size:15px;line-height:1.6;">
		    Đơn hàng <span style="color:%s;font-weight:600;">%s</span> đã được thanh toán thành công
		    qua <strong>%s</strong>.
		  </p>
		  <table role="presentation" cellpadding="0" cellspacing="0" border="0"
		         style="width:100%%;border-collapse:collapse;font-size:14px;margin:16px 0;">
		    <tr><td style="padding:10px 12px;background:%s;color:%s;width:40%%;">Mã giao dịch</td>
		        <td style="padding:10px 12px;background:%s;font-weight:600;">%s</td></tr>
		    <tr><td style="padding:10px 12px;color:%s;">Phương thức</td>
		        <td style="padding:10px 12px;font-weight:600;">%s</td></tr>
		    <tr><td style="padding:10px 12px;background:%s;color:%s;">Thời gian</td>
		        <td style="padding:10px 12px;background:%s;font-weight:600;">%s</td></tr>
		  </table>
		  %s
		  <p style="margin:24px 0 0 0;text-align:center;font-size:14px;">
		    Cảm ơn bạn đã mua sắm tại <strong style="color:%s;">Tropia!</strong>
		  </p>
		  <p style="margin:8px 0 0 0;text-align:center;color:%s;font-size:13px;">
		    Đơn hàng sẽ được giao trong 1–3 ngày làm việc.
		  </p>
		</div>`,
		brandPrimary, brandDark, brandPrimary,
		time.Now().Format("15:04:05 02/01/2006"),
		in.Name, brandPrimary, in.OrderID, in.Method,
		brandLight, brandMuted, brandLight, in.TransactionID,
		brandMuted, in.Method,
		brandLight, brandMuted, brandLight, time.Now().Format("15:04:05 02/01/2006"),
		itemsSection,
		brandPrimary, brandMuted))
	return subject, body
}

// PaymentSuccessInput bundles everything the receipt email needs.
type PaymentSuccessInput struct {
	Name           string        // recipient display name
	OrderID        string        // UUID or human-friendly id
	Method         string        // MoMo / VNPay / ZaloPay
	TransactionID  string        // gateway-specific txn id
	TotalPrice     int           // final amount after discount (VND)
	DiscountAmount int           // 0 = no voucher line
	Items          []PaymentItem // empty → omit product table
}

// ── helpers ─────────────────────────────────────────────────────────────────

// formatVND turns 21250 → "21.250".
func formatVND(n int) string {
	neg := n < 0
	if neg {
		n = -n
	}
	s := fmt.Sprintf("%d", n)
	var out strings.Builder
	if neg {
		out.WriteByte('-')
	}
	// Insert dots every 3 digits from the right.
	rem := len(s) % 3
	if rem == 0 {
		rem = 3
	}
	out.WriteString(s[:rem])
	for i := rem; i < len(s); i += 3 {
		out.WriteByte('.')
		out.WriteString(s[i : i+3])
	}
	return out.String()
}

// escapeHTML — minimal, enough for product names in receipts.
func escapeHTML(s string) string {
	r := strings.NewReplacer(
		"&", "&amp;",
		"<", "&lt;",
		">", "&gt;",
		`"`, "&quot;",
	)
	return r.Replace(s)
}
