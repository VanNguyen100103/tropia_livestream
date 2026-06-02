package live

import (
	"regexp"
	"strings"
)

// chatURLPattern matches the common URL shapes that scam/phishing chat
// spam relies on: scheme-prefixed, www-prefixed, bare-domain with a TLD,
// and obfuscated forms like "shopee dot vn" / "shopee[.]vn". It deliberately
// over-matches — chat is a conversational channel where false positives
// (a buyer asking "go to shop.vn") are cheaper than scam links slipping
// through. Threat 9 (chat manipulation: scam links, raid).
var chatURLPattern = regexp.MustCompile(
	`(?i)(` +
		`https?://\S+` + // http(s)://...
		`|` +
		`www\.[a-z0-9-]+\.[a-z]{2,}` + // www.foo.com
		`|` +
		`[a-z0-9-]+\.(?:com|net|org|vn|io|me|co|biz|info|xyz|live|store|shop)\b` + // bare domain (whitelisted TLDs to cut noise)
		`|` +
		`[a-z0-9-]+\s*(?:\[\.\]|\(\.\)|\s+dot\s+)\s*[a-z0-9-]+` + // obfuscated: "shopee[.]vn", "shopee dot vn"
		`)`,
)

// chatBlockedPhrases are case-insensitive substring matches for the most
// common Vietnamese ecommerce scams. Curated to favour high-precision
// patterns — broad keywords like "tiền" or "shop" would catch normal chat.
var chatBlockedPhrases = []string{
	"chuyển khoản trước",
	"nạp thẻ",
	"thẻ cào",
	"link đặt hàng riêng",
	"add zalo",
	"kb zalo",
	"nhắn tin riêng",
	"check tin nhắn",
	"liên hệ ngoài",
	"giao dịch ngoài app",
	"telegram",
	"@gmail.com",
	"@yahoo.com",
}

// FilterChatMessage classifies an incoming chat message. Returns:
//   - sanitized: message with URLs masked as "[link bị chặn]" so the
//     conversation flow stays but the link is unusable;
//   - blocked: true when the message hits a phrase blocklist and should
//     be rejected outright rather than masked. Caller returns 400 in
//     that case.
//
// Host messages bypass this filter (sellers legitimately share their own
// shop URL). The caller is responsible for the host check.
func FilterChatMessage(raw string) (sanitized string, blocked bool) {
	lower := strings.ToLower(raw)
	for _, phrase := range chatBlockedPhrases {
		if strings.Contains(lower, phrase) {
			return raw, true
		}
	}
	sanitized = chatURLPattern.ReplaceAllString(raw, "[link bị chặn]")
	return sanitized, false
}
