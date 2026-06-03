package payment

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"
)

// MoMo payment client (sandbox-ready).
// Signature scheme: HMAC-SHA256 over fixed-order "key=value&key=value" string.

type MoMoConfig struct {
	PartnerCode string
	AccessKey   string
	SecretKey   string
	APIURL      string // https://test-payment.momo.vn or https://payment.momo.vn
	RedirectURL string
	IPNURL      string
}

type MoMo struct{ cfg MoMoConfig }

// paymentHTTPClient — bounded timeout so a stuck MoMo/ZaloPay endpoint
// can't pin a request goroutine forever. 15s covers the slow-but-alive
// case (sandbox under load) while killing genuinely dead connections.
var paymentHTTPClient = &http.Client{Timeout: 15 * time.Second}

func NewMoMo(cfg MoMoConfig) *MoMo { return &MoMo{cfg: cfg} }

type MoMoCreateInput struct {
	OrderID    string
	Amount     int
	OrderInfo  string
	ExtraData  string
}

type MoMoCreateResult struct {
	PayURL    string `json:"payUrl"`
	Deeplink  string `json:"deeplink"`
	QRCodeURL string `json:"qrCodeUrl"`
	RequestID string `json:"requestId"`
}

func (m *MoMo) Create(ctx context.Context, in MoMoCreateInput) (*MoMoCreateResult, error) {
	requestID := m.cfg.PartnerCode + strconv.FormatInt(time.Now().UnixMilli(), 10)
	extraData := base64.StdEncoding.EncodeToString([]byte(in.ExtraData))

	rawSig := fmt.Sprintf("accessKey=%s&amount=%d&extraData=%s&ipnUrl=%s&orderId=%s&orderInfo=%s&partnerCode=%s&redirectUrl=%s&requestId=%s&requestType=payWithMethod",
		m.cfg.AccessKey, in.Amount, extraData, m.cfg.IPNURL,
		in.OrderID, in.OrderInfo, m.cfg.PartnerCode, m.cfg.RedirectURL, requestID,
	)
	sig := hmacSHA256Hex(m.cfg.SecretKey, rawSig)

	payload := map[string]any{
		"partnerCode":  m.cfg.PartnerCode,
		"accessKey":    m.cfg.AccessKey,
		"requestId":    requestID,
		"amount":       in.Amount,
		"orderId":      in.OrderID,
		"orderInfo":    in.OrderInfo,
		"redirectUrl":  m.cfg.RedirectURL,
		"ipnUrl":       m.cfg.IPNURL,
		"extraData":    extraData,
		"requestType":  "payWithMethod",
		"autoCapture":  true,
		"lang":         "vi",
		"signature":    sig,
	}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(ctx, "POST", m.cfg.APIURL+"/v2/gateway/api/create", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := paymentHTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	rb, _ := io.ReadAll(resp.Body)
	var out struct {
		ResultCode int    `json:"resultCode"`
		Message    string `json:"message"`
		MoMoCreateResult
	}
	if err := json.Unmarshal(rb, &out); err != nil {
		return nil, err
	}
	if out.ResultCode != 0 {
		return nil, fmt.Errorf("momo error %d: %s", out.ResultCode, out.Message)
	}
	out.MoMoCreateResult.RequestID = requestID
	return &out.MoMoCreateResult, nil
}

// MoMoIPN - body sent by MoMo webhook
type MoMoIPN struct {
	PartnerCode  string `json:"partnerCode"`
	OrderID      string `json:"orderId"`
	RequestID    string `json:"requestId"`
	Amount       int64  `json:"amount"`
	OrderInfo    string `json:"orderInfo"`
	OrderType    string `json:"orderType"`
	TransID      int64  `json:"transId"`
	ResultCode   int    `json:"resultCode"`
	Message      string `json:"message"`
	PayType      string `json:"payType"`
	ResponseTime int64  `json:"responseTime"`
	ExtraData    string `json:"extraData"`
	Signature    string `json:"signature"`
}

// VerifyIPN validates signature using 13-field raw string format.
func (m *MoMo) VerifyIPN(ipn *MoMoIPN) bool {
	raw := fmt.Sprintf("accessKey=%s&amount=%d&extraData=%s&message=%s&orderId=%s&orderInfo=%s&orderType=%s&partnerCode=%s&payType=%s&requestId=%s&responseTime=%d&resultCode=%d&transId=%d",
		m.cfg.AccessKey, ipn.Amount, ipn.ExtraData, ipn.Message,
		ipn.OrderID, ipn.OrderInfo, ipn.OrderType, ipn.PartnerCode,
		ipn.PayType, ipn.RequestID, ipn.ResponseTime, ipn.ResultCode, ipn.TransID,
	)
	expected := hmacSHA256Hex(m.cfg.SecretKey, raw)
	return hmac.Equal([]byte(expected), []byte(ipn.Signature))
}

// DecodeExtraData - base64 decode
func DecodeExtraData(extraData string) string {
	b, err := base64.StdEncoding.DecodeString(extraData)
	if err != nil {
		return ""
	}
	return string(b)
}

func hmacSHA256Hex(secret, s string) string {
	h := hmac.New(sha256.New, []byte(secret))
	h.Write([]byte(s))
	return hex.EncodeToString(h.Sum(nil))
}
