package vod

import (
	"strconv"
	"strings"
)

// FormatVND renders a VND amount as "175.000đ": whole dong, '.' thousands
// separators, trailing 'đ' — matching how the app shows prices. The baked
// overlays previously used fmt's "%.0fđ", which dropped the separators
// ("175000đ") and read as a glitch next to the live UI. Exported so the
// worker (coupon labels) shares one formatter with the renderers.
func FormatVND(v float64) string {
	var n int64
	if v >= 0 {
		n = int64(v + 0.5)
	} else {
		n = int64(v - 0.5)
	}
	neg := n < 0
	if neg {
		n = -n
	}
	digits := strconv.FormatInt(n, 10)

	var b strings.Builder
	if neg {
		b.WriteByte('-')
	}
	head := len(digits) % 3
	if head == 0 {
		head = 3
	}
	b.WriteString(digits[:head])
	for i := head; i < len(digits); i += 3 {
		b.WriteByte('.')
		b.WriteString(digits[i : i+3])
	}
	b.WriteString("đ")
	return b.String()
}
