package payment

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strconv"
	"time"
)

// ZaloPay (sandbox-ready).
//
// Create signature: HMAC-SHA256 over
//   {appId}|{appTransId}|{appUser}|{amount}|{appTime}|{embedData}|{item}
// using key1.
//
// Callback signature: HMAC-SHA256 over the raw `data` JSON string using key2.

type ZaloPayConfig struct {
	AppID       string
	Key1        string
	Key2        string
	APICreate   string
	APIQuery    string
	CallbackURL string
	RedirectURL string
}

type ZaloPay struct{ cfg ZaloPayConfig }

func NewZaloPay(cfg ZaloPayConfig) *ZaloPay { return &ZaloPay{cfg: cfg} }

type ZaloPayCreateInput struct {
	OrderID     string
	Amount      int
	Description string
	AppUser     string
}

type ZaloPayCreateResult struct {
	OrderURL      string `json:"order_url"`
	ZpTransToken  string `json:"zp_trans_token"`
	OrderToken    string `json:"order_token"`
	AppTransID    string `json:"app_trans_id"`
}

// makeAppTransID returns "yyMMdd_<random>" — matches ZaloPay spec
// (yyMMdd prefix is required). The random tail uses crypto/rand so the
// resulting app_trans_id is unpredictable; math/rand would let an attacker
// enumerate / spoof in-flight transaction IDs.
func makeAppTransID(orderID string) string {
	now := time.Now().In(vietnamLoc())
	prefix := now.Format("060102")
	n, err := rand.Int(rand.Reader, big.NewInt(1_000_000_000))
	if err != nil {
		// crypto/rand failure is fatal in practice; fall back to a
		// time-derived tail rather than 0 so transactions stay distinct.
		return fmt.Sprintf("%s_%d", prefix, now.UnixNano())
	}
	return fmt.Sprintf("%s_%09d", prefix, n.Int64())
}

func vietnamLoc() *time.Location {
	loc, err := time.LoadLocation("Asia/Ho_Chi_Minh")
	if err != nil {
		return time.FixedZone("ICT", 7*3600)
	}
	return loc
}

func (z *ZaloPay) Create(ctx context.Context, in ZaloPayCreateInput) (*ZaloPayCreateResult, error) {
	appTransID := makeAppTransID(in.OrderID)
	appTime := time.Now().UnixMilli()

	embedData, _ := json.Marshal(map[string]any{
		"orderId":     in.OrderID,
		"redirecturl": z.cfg.RedirectURL,
	})
	items, _ := json.Marshal([]any{})

	rawSig := fmt.Sprintf("%s|%s|%s|%d|%d|%s|%s",
		z.cfg.AppID, appTransID, in.AppUser, in.Amount, appTime, embedData, items,
	)
	mac := hmacSHA256Hex(z.cfg.Key1, rawSig)

	form := map[string]any{
		"app_id":        z.cfg.AppID,
		"app_trans_id":  appTransID,
		"app_user":      in.AppUser,
		"app_time":      appTime,
		"amount":        in.Amount,
		"item":          string(items),
		"embed_data":    string(embedData),
		"description":   in.Description,
		"bank_code":     "",
		"callback_url":  z.cfg.CallbackURL,
		"mac":           mac,
	}

	body, _ := json.Marshal(form)
	req, err := http.NewRequestWithContext(ctx, "POST", z.cfg.APICreate, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := paymentHTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)

	var out struct {
		ReturnCode    int    `json:"return_code"`
		ReturnMessage string `json:"return_message"`
		SubReturnCode int    `json:"sub_return_code"`
		ZaloPayCreateResult
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, err
	}
	if out.ReturnCode != 1 {
		return nil, fmt.Errorf("zalopay %d/%d: %s", out.ReturnCode, out.SubReturnCode, out.ReturnMessage)
	}
	out.ZaloPayCreateResult.AppTransID = appTransID
	return &out.ZaloPayCreateResult, nil
}

// VerifyCallback - validates the MAC over raw `data` string from the
// callback body using key2. Returns the parsed embed_data (which holds
// our orderId) if valid.
type ZaloPayCallback struct {
	Data string `json:"data"`
	Mac  string `json:"mac"`
	Type int    `json:"type"`
}

type ZaloPayCallbackData struct {
	AppID         int    `json:"app_id"`
	AppTransID    string `json:"app_trans_id"`
	Amount        int    `json:"amount"`
	EmbedData     string `json:"embed_data"`
	ZpTransID     int64  `json:"zp_trans_id"`
	ServerTime    int64  `json:"server_time"`
	UserFeeAmount int    `json:"user_fee_amount"`
}

type ZaloPayCallbackResult struct {
	Valid       bool
	Data        ZaloPayCallbackData
	OrderID     string
	TxID        string
}

func (z *ZaloPay) VerifyCallback(cb *ZaloPayCallback) (*ZaloPayCallbackResult, error) {
	expected := hmacSHA256Hex(z.cfg.Key2, cb.Data)
	if !hmac.Equal([]byte(expected), []byte(cb.Mac)) {
		return &ZaloPayCallbackResult{Valid: false}, nil
	}
	var data ZaloPayCallbackData
	if err := json.Unmarshal([]byte(cb.Data), &data); err != nil {
		return nil, err
	}
	var embed map[string]any
	_ = json.Unmarshal([]byte(data.EmbedData), &embed)
	orderID, _ := embed["orderId"].(string)

	return &ZaloPayCallbackResult{
		Valid:   true,
		Data:    data,
		OrderID: orderID,
		TxID:    strconv.FormatInt(data.ZpTransID, 10),
	}, nil
}
