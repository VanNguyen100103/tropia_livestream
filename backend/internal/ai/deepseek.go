package ai

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"time"
)

type DeepSeek struct {
	apiKey string
	url    string
	model  string
	client *http.Client
}

func NewDeepSeek(apiKey string) *DeepSeek {
	return &DeepSeek{
		apiKey: apiKey,
		url:    "https://api.deepseek.com/chat/completions",
		model:  "deepseek-chat",
		client: &http.Client{Timeout: 15 * time.Second},
	}
}

// IsConfigured reports whether DEEPSEEK_API_KEY was provided. Callers can
// short-circuit the goroutine before bothering with DB lookups when the key
// is missing, instead of waiting for the HTTP call to fail.
func (d *DeepSeek) IsConfigured() bool { return d != nil && d.apiKey != "" }

type chatMsg struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type chatReq struct {
	Model    string    `json:"model"`
	Messages []chatMsg `json:"messages"`
	Temp     float32   `json:"temperature,omitempty"`
}

type chatResp struct {
	Choices []struct {
		Message chatMsg `json:"message"`
	} `json:"choices"`
}

func (d *DeepSeek) call(ctx context.Context, system, user string) (string, error) {
	if d.apiKey == "" {
		return "", errors.New("deepseek api key not set")
	}
	body, _ := json.Marshal(chatReq{
		Model: d.model,
		Messages: []chatMsg{
			{Role: "system", Content: system},
			{Role: "user", Content: user},
		},
		Temp: 0.7,
	})
	req, err := http.NewRequestWithContext(ctx, "POST", d.url, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+d.apiKey)
	req.Header.Set("Content-Type", "application/json")
	resp, err := d.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("deepseek status %d", resp.StatusCode)
	}
	var r chatResp
	if err := json.NewDecoder(resp.Body).Decode(&r); err != nil {
		return "", err
	}
	if len(r.Choices) == 0 {
		return "", errors.New("empty response")
	}
	return r.Choices[0].Message.Content, nil
}

// SuggestionProduct is a minimal product hint the AI uses to draft
// viewer-style questions. Keep it small — DeepSeek context cost scales
// with prompt length.
type SuggestionProduct struct {
	Name     string
	Price    float64 // optional, 0 = unknown
	Category string  // optional
}

// CouponHint feeds active session coupons into the bot prompt so the AI
// can reference real codes/discount amounts when a viewer asks about
// promotions, instead of inventing a generic "mua 2 tặng 1" reply.
type CouponHint struct {
	Code          string
	DiscountType  string // "percent" or "fixed"
	DiscountValue float64
	MinOrderValue int // in VND; 0 = no minimum
}

// formatCouponsForPrompt builds a Vietnamese-language bullet list of
// active coupons for inclusion in the system prompt. Returns "" if no
// coupons so callers can skip the section entirely.
func formatCouponsForPrompt(coupons []CouponHint) string {
	if len(coupons) == 0 {
		return ""
	}
	var lines []string
	for _, c := range coupons {
		var seg string
		if c.DiscountType == "percent" {
			seg = fmt.Sprintf("%s: giảm %.0f%%", c.Code, c.DiscountValue)
		} else {
			seg = fmt.Sprintf("%s: giảm %s", c.Code, formatVND(c.DiscountValue))
		}
		if c.MinOrderValue > 0 {
			seg += fmt.Sprintf(", đơn từ %s", formatVND(float64(c.MinOrderValue)))
		}
		lines = append(lines, "- "+seg)
	}
	return joinLines(lines)
}

// formatVND renders an amount in VND as "100K" / "1.5M" — matches how
// Vietnamese livestream hosts speak about prices on-air.
func formatVND(v float64) string {
	switch {
	case v >= 1_000_000:
		return fmt.Sprintf("%.1fM đ", v/1_000_000)
	case v >= 1_000:
		return fmt.Sprintf("%.0fK đ", v/1_000)
	default:
		return fmt.Sprintf("%.0f đ", v)
	}
}

// GetSuggestions returns 3-5 short Vietnamese viewer questions covering a
// mix of topics (price, shipping, storage, variants, promotions) so the
// host gets useful prompts instead of three near-duplicate questions.
//
// Pass the list of pinned products from the live session — the AI will
// reference real product names and rotate topics across them. If
// `coupons` is non-empty, the price/promo question may reference a real
// coupon code instead of asking a generic "có giảm giá không".
func (d *DeepSeek) GetSuggestions(ctx context.Context, products []SuggestionProduct, fallbackCategory string, coupons []CouponHint) ([]string, error) {
	if len(products) == 0 {
		// No pinned products — still useful to show generic intro questions.
		products = []SuggestionProduct{{Name: "sản phẩm", Category: fallbackCategory}}
	}

	// Build a compact product list for the prompt.
	var lines []string
	for i, p := range products {
		if i >= 5 { // cap — DeepSeek doesn't need the whole catalog
			break
		}
		seg := p.Name
		if p.Price > 0 {
			seg += fmt.Sprintf(" (%.0fk)", p.Price/1000)
		}
		if p.Category != "" {
			seg += " - " + p.Category
		}
		lines = append(lines, "- "+seg)
	}
	productBlock := joinLines(lines)

	system := `Bạn đóng vai NHIỀU người mua đang xem livestream bán hàng Việt Nam.
Trả về CHÍNH XÁC 4 câu hỏi ngắn (mỗi câu < 15 từ), MỖI CÂU MỘT DÒNG, KHÔNG đánh số.
Mỗi câu hỏi phải nhắc đến TÊN SẢN PHẨM CỤ THỂ trong danh sách và TẬP TRUNG VÀO MỘT chủ đề KHÁC NHAU:
  1) Giá / khuyến mãi / so sánh giá thị trường
  2) Giao hàng / phí ship / thời gian giao
  3) Bảo quản / hạn sử dụng / cách dùng
  4) Biến thể / size / số lượng còn / combo
Giọng tự nhiên, dùng "shop ơi" hoặc "ạ" cuối câu.`
	userParts := []string{"Danh sách sản phẩm host đang ghim:\n" + productBlock}
	if cb := formatCouponsForPrompt(coupons); cb != "" {
		userParts = append(userParts,
			"Mã giảm giá đang phát trong live (câu hỏi về giá/khuyến mãi NÊN hỏi đúng mã này):\n"+cb)
	}
	user := joinSections(userParts)

	out, err := d.call(ctx, system, user)
	if err != nil {
		return nil, err
	}
	var result []string
	for _, ln := range splitLines(out) {
		if ln == "" {
			continue
		}
		// Strip leading bullets/numbers if model ignored the instruction.
		ln = trimBulletPrefix(ln)
		if ln != "" {
			result = append(result, ln)
		}
	}
	if len(result) > 5 {
		result = result[:5]
	}
	return result, nil
}

// trimBulletPrefix strips common list prefixes ("1.", "- ", "* ") in case
// the model emits a numbered list despite the system prompt forbidding it.
func trimBulletPrefix(s string) string {
	for _, prefix := range []string{"- ", "* ", "• "} {
		if len(s) > len(prefix) && s[:len(prefix)] == prefix {
			return s[len(prefix):]
		}
	}
	// Numbered: "1. ", "2) "
	if len(s) >= 3 && s[0] >= '1' && s[0] <= '9' &&
		(s[1] == '.' || s[1] == ')') && s[2] == ' ' {
		return s[3:]
	}
	return s
}

func joinLines(lines []string) string {
	out := ""
	for i, ln := range lines {
		if i > 0 {
			out += "\n"
		}
		out += ln
	}
	return out
}

// joinSections concatenates prompt sections with a blank line between
// them so DeepSeek treats each as a separate context block.
func joinSections(parts []string) string {
	out := ""
	for i, p := range parts {
		if i > 0 {
			out += "\n\n"
		}
		out += p
	}
	return out
}

func (d *DeepSeek) GetAutoReply(ctx context.Context, question, productName, category string, coupons []CouponHint) (string, error) {
	system := `Bạn là chủ shop livestream Việt Nam. Trả lời ngắn (< 25 từ), giọng tự nhiên.
TUYỆT ĐỐI KHÔNG được bịa khuyến mãi không có trong dữ liệu (ví dụ "mua 2 tặng 1").
Khi khách hỏi về giá, giảm giá, khuyến mãi, mã coupon: chỉ nhắc tới mã giảm giá đang phát (nếu có trong danh sách bên dưới); nếu không có thì nói thẳng là hiện chỉ có giá niêm yết.`
	if cb := formatCouponsForPrompt(coupons); cb != "" {
		system += "\n\nMã giảm giá đang phát trong live này:\n" + cb
	} else {
		system += "\n\nHiện không có mã giảm giá nào đang phát."
	}
	user := fmt.Sprintf("Sản phẩm: %s. Loại: %s. Câu hỏi: %s", productName, category, question)
	return d.call(ctx, system, user)
}

type Sentiment struct {
	Sentiment string   `json:"sentiment"`
	Summary   string   `json:"summary"`
	Tips      []string `json:"tips"`
}

var sentimentRe = regexp.MustCompile(`(?s)\{[\s\S]*"sentiment"[\s\S]*\}`)

func (d *DeepSeek) AnalyzeSentiment(ctx context.Context, title string, viewers, likes int) (*Sentiment, error) {
	system := `Bạn là tư vấn livestream. Phân tích và trả về JSON: {"sentiment":"tích cực|trung bình|cần cải thiện","summary":"...","tips":["...","...","...","..."]}`
	user := fmt.Sprintf("Live: %s. Viewers: %d. Likes: %d.", title, viewers, likes)
	raw, err := d.call(ctx, system, user)
	if err != nil {
		return nil, err
	}
	match := sentimentRe.FindString(raw)
	if match == "" {
		return nil, errors.New("invalid response")
	}
	var s Sentiment
	if err := json.Unmarshal([]byte(match), &s); err != nil {
		return nil, err
	}
	return &s, nil
}

func splitLines(s string) []string {
	out := []string{}
	cur := ""
	for _, r := range s {
		if r == '\n' || r == '\r' {
			if cur != "" {
				out = append(out, cur)
			}
			cur = ""
		} else {
			cur += string(r)
		}
	}
	if cur != "" {
		out = append(out, cur)
	}
	return out
}
