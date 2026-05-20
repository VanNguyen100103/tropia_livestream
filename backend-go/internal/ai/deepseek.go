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

// GetSuggestions - 3 short Vietnamese viewer questions
func (d *DeepSeek) GetSuggestions(ctx context.Context, productName, category string) ([]string, error) {
	system := "Bạn là viewer xem live bán hàng Việt Nam. Trả về CHÍNH XÁC 3 câu hỏi ngắn (mỗi câu < 15 từ), mỗi câu một dòng, không số thứ tự."
	user := fmt.Sprintf("Sản phẩm: %s. Loại: %s. Tạo 3 câu hỏi thường gặp.", productName, category)
	out, err := d.call(ctx, system, user)
	if err != nil {
		return nil, err
	}
	lines := []string{}
	for _, ln := range splitLines(out) {
		if ln != "" {
			lines = append(lines, ln)
		}
	}
	if len(lines) > 3 {
		lines = lines[:3]
	}
	return lines, nil
}

func (d *DeepSeek) GetAutoReply(ctx context.Context, question, productName, category string) (string, error) {
	system := "Bạn là chủ shop livestream. Trả lời ngắn (< 20 từ), giọng tự nhiên."
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
