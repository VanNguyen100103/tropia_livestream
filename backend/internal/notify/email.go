package notify

import (
	"crypto/tls"
	"fmt"
	"net/smtp"
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

// ---------- Templates ----------

func TmplOTP(name, otp string) (string, string) {
	subject := "Mã xác thực Tropia"
	body := fmt.Sprintf(`
		<div style="font-family:Arial,sans-serif">
		<h2>Xin chào %s,</h2>
		<p>Mã xác thực email của bạn là:</p>
		<h1 style="letter-spacing:6px">%s</h1>
		<p>Mã có hiệu lực trong 10 phút.</p>
		</div>`, name, otp)
	return subject, body
}

func TmplWelcome(name string) (string, string) {
	subject := "Chào mừng đến với Tropia 🍎"
	body := fmt.Sprintf(`<h2>Chào %s</h2><p>Cảm ơn bạn đã đăng ký Tropia.</p>`, name)
	return subject, body
}

func TmplPasswordReset(name, link string) (string, string) {
	subject := "Yêu cầu đặt lại mật khẩu Tropia"
	body := fmt.Sprintf(`
		<p>Xin chào %s,</p>
		<p>Click <a href="%s">vào đây</a> để đặt lại mật khẩu. Liên kết có hiệu lực 1 giờ.</p>`, name, link)
	return subject, body
}

func TmplOrderConfirm(name string, orderID string, total int) (string, string) {
	subject := "Xác nhận đơn hàng Tropia"
	body := fmt.Sprintf(`<p>Xin chào %s,</p><p>Đơn hàng <b>%s</b> đã được tiếp nhận, tổng %d VND.</p>`, name, orderID, total)
	return subject, body
}

func TmplPaymentSuccess(name, orderID, method string, total int) (string, string) {
	subject := "Thanh toán thành công - Tropia"
	body := fmt.Sprintf(`<p>Xin chào %s,</p><p>Đơn hàng <b>%s</b> đã được thanh toán qua %s, tổng %d VND.</p>`, name, orderID, method, total)
	return subject, body
}
