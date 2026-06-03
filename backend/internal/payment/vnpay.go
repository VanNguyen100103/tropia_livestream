package payment

import (
	"crypto/hmac"
	"crypto/sha512"
	"encoding/hex"
	"fmt"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
)

type VNPayConfig struct {
	TMNCode    string
	HashSecret string
	URL        string // sandbox or production
	ReturnURL  string
}

type VNPay struct{ cfg VNPayConfig }

func NewVNPay(cfg VNPayConfig) *VNPay { return &VNPay{cfg: cfg} }

// BuildPayURL - returns URL for user to redirect to
func (v *VNPay) BuildPayURL(orderID string, amount int, ipAddr, locale string) string {
	if locale == "" {
		locale = "vn"
	}
	now := time.Now()
	// Asia/Ho_Chi_Minh
	loc, _ := time.LoadLocation("Asia/Ho_Chi_Minh")
	now = now.In(loc)
	createDate := now.Format("20060102150405")
	expireDate := now.Add(15 * time.Minute).Format("20060102150405")

	params := map[string]string{
		"vnp_Version":    "2.1.0",
		"vnp_Command":    "pay",
		"vnp_TmnCode":    v.cfg.TMNCode,
		"vnp_Amount":     strconv.Itoa(amount * 100),
		"vnp_CurrCode":   "VND",
		"vnp_TxnRef":     orderID,
		"vnp_OrderInfo":  "Thanh toan don hang " + orderID,
		"vnp_OrderType":  "other",
		"vnp_Locale":     locale,
		"vnp_ReturnUrl":  v.cfg.ReturnURL,
		"vnp_IpAddr":     ipAddr,
		"vnp_CreateDate": createDate,
		"vnp_ExpireDate": expireDate,
	}

	// Sort alphabetically and build query
	keys := make([]string, 0, len(params))
	for k := range params {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var raw strings.Builder
	for i, k := range keys {
		if i > 0 {
			raw.WriteByte('&')
		}
		raw.WriteString(k)
		raw.WriteByte('=')
		raw.WriteString(params[k])
	}
	signed := hmacSHA512Hex(v.cfg.HashSecret, raw.String())

	// Build final URL with proper URL-encoding
	q := url.Values{}
	for _, k := range keys {
		q.Set(k, params[k])
	}
	q.Set("vnp_SecureHash", signed)
	return v.cfg.URL + "?" + q.Encode()
}

// VerifyReturn checks the HMAC of vnp_SecureHash from query string.
func (v *VNPay) VerifyReturn(values url.Values) bool {
	provided := values.Get("vnp_SecureHash")
	values.Del("vnp_SecureHash")
	values.Del("vnp_SecureHashType")

	keys := make([]string, 0, len(values))
	for k := range values {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var raw strings.Builder
	for i, k := range keys {
		if i > 0 {
			raw.WriteByte('&')
		}
		raw.WriteString(k)
		raw.WriteByte('=')
		raw.WriteString(values.Get(k))
	}
	expected := hmacSHA512Hex(v.cfg.HashSecret, raw.String())
	return hmac.Equal([]byte(strings.ToLower(expected)), []byte(strings.ToLower(provided)))
}

// ExtractOrderID - reverse of "Thanh toan don hang {orderID}"
func ExtractVNPayOrderID(orderInfo string) string {
	prefix := "Thanh toan don hang "
	if strings.HasPrefix(orderInfo, prefix) {
		return strings.TrimPrefix(orderInfo, prefix)
	}
	return orderInfo
}

func hmacSHA512Hex(secret, s string) string {
	h := hmac.New(sha512.New, []byte(secret))
	h.Write([]byte(s))
	return hex.EncodeToString(h.Sum(nil))
}

// guard against unused import in some scenarios
var _ = fmt.Sprintf
