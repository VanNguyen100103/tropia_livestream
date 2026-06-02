package httpx

import (
	"bufio"
	"bytes"
	"encoding/json"
	"net"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// ─────────────────────────────────────────────────────────────────────────
// Response envelope (LIVESTREAM_API.md §1)
//
// Every JSON response in the system is wrapped in this shape:
//
//	{
//	  "Result":     true,
//	  "StatusCode": "200",
//	  "StatusMess": "Success",
//	  "status":     200,
//	  "message":    "Success",
//	  "data":       {...} | [...] | null
//	}
//
// Rather than rewrite every `c.JSON(...)` call site, an EnvelopeWrapper
// middleware buffers the handler's JSON body and re-emits it inside the
// envelope. Handlers keep returning their natural payloads; the wrapper
// turns the payload into `data`, derives Result/StatusCode from the HTTP
// status, and lifts any "message"/"error" field up to StatusMess/message.
//
// Streaming / binary / WebSocket responses (HLS, /ws/*, file downloads,
// redirects, /health, /metrics, /docs) bypass the wrapper untouched.
// ─────────────────────────────────────────────────────────────────────────

// Envelope is the canonical response shape.
type Envelope struct {
	Result     bool   `json:"Result"`
	StatusCode string `json:"StatusCode"`
	StatusMess string `json:"StatusMess"`
	Status     int    `json:"status"`
	Message    string `json:"message"`
	Data       any    `json:"data"`
}

const ctxEnvelopeMessage = "envelope.message"

// SetMessage overrides the StatusMess/message a handler's response will
// carry inside the envelope. Use it from handlers that want a specific
// Vietnamese success message (e.g. "Đăng nhập thành công"). When unset,
// the wrapper falls back to a default message for the HTTP status code,
// or to a "message"/"error" field found in the body.
func SetMessage(c *gin.Context, msg string) {
	c.Set(ctxEnvelopeMessage, msg)
}

// defaultMessage maps an HTTP status to a Vietnamese default message used
// when neither the handler nor the body supplied one.
func defaultMessage(status int) string {
	switch {
	case status >= 200 && status < 300:
		return "Success"
	case status == http.StatusBadRequest:
		return "Yêu cầu không hợp lệ"
	case status == http.StatusUnauthorized:
		return "Chưa xác thực hoặc token không hợp lệ"
	case status == http.StatusForbidden:
		return "Không có quyền truy cập"
	case status == http.StatusNotFound:
		return "Không tìm thấy"
	case status == http.StatusTooManyRequests:
		return "Quá nhiều yêu cầu, vui lòng thử lại sau"
	case status >= 500:
		return "Lỗi hệ thống"
	default:
		return http.StatusText(status)
	}
}

// EnvelopeWrapper wraps every eligible JSON response in the standard
// envelope. Register it once, before the route handlers and the
// ErrorHandler, so its buffering writer is active for their output.
func EnvelopeWrapper() gin.HandlerFunc {
	return func(c *gin.Context) {
		if skipEnvelope(c) {
			c.Next()
			return
		}
		orig := c.Writer
		cap := &bodyCapture{ResponseWriter: orig}
		c.Writer = cap
		c.Next()
		c.Writer = orig

		// A WebSocket upgrade (or any handler that hijacked the conn)
		// took the socket over directly — nothing to wrap.
		if cap.hijacked {
			return
		}

		status := cap.status
		if status == 0 {
			status = http.StatusOK
		}

		header := orig.Header()
		// Redirects carry a Location and an empty/non-JSON body — leave
		// them alone so the browser/app follows the 3xx.
		if header.Get("Location") != "" || (status >= 300 && status < 400) {
			orig.WriteHeader(status)
			_, _ = orig.Write(cap.buf.Bytes())
			return
		}

		raw := cap.buf.Bytes()
		ct := header.Get("Content-Type")
		// Non-JSON payloads (files, plain text) pass through verbatim.
		if len(raw) > 0 && !strings.Contains(ct, "application/json") {
			orig.WriteHeader(status)
			_, _ = orig.Write(raw)
			return
		}

		env := buildEnvelope(c, status, raw)
		out, err := json.Marshal(env)
		if err != nil {
			orig.WriteHeader(http.StatusInternalServerError)
			return
		}
		header.Set("Content-Type", "application/json; charset=utf-8")
		// The buffered body length no longer matches the envelope we're
		// about to write; let net/http recompute it.
		header.Del("Content-Length")
		// The envelope normalises every response to a 200-class HTTP code
		// when it succeeded; failures keep their status so proxies/log
		// tooling still see the real code.
		orig.WriteHeader(status)
		_, _ = orig.Write(out)
	}
}

// buildEnvelope converts a captured handler body + status into the
// envelope. The body becomes `data`; a top-level "message" or "error"
// field (if present) is lifted into StatusMess/message.
func buildEnvelope(c *gin.Context, status int, raw []byte) Envelope {
	success := status >= 200 && status < 400
	msg := ""
	var data any

	if len(bytes.TrimSpace(raw)) > 0 {
		var parsed any
		if err := json.Unmarshal(raw, &parsed); err == nil {
			data = parsed
			if obj, ok := parsed.(map[string]any); ok {
				if !success {
					// Error bodies from ErrorHandler look like
					// {"error": "...", "code": "..."} — surface the
					// human message and drop the wrapper object so
					// `data` is null on failures (per spec examples).
					if e, ok := obj["error"].(string); ok && e != "" {
						msg = e
						data = nil
					}
				} else if m, ok := obj["message"].(string); ok && m != "" {
					msg = m
				}
			}
		} else {
			// Body wasn't valid JSON — stash it as a string so we never
			// silently drop a handler's output.
			data = string(raw)
		}
	}

	// Handler-supplied message wins over everything.
	if override, ok := c.Get(ctxEnvelopeMessage); ok {
		if s, ok := override.(string); ok && s != "" {
			msg = s
		}
	}
	if msg == "" {
		msg = defaultMessage(status)
	}

	return Envelope{
		Result:     success,
		StatusCode: strconv.Itoa(status),
		StatusMess: msg,
		Status:     status,
		Message:    msg,
		Data:       data,
	}
}

// skipEnvelope returns true for responses that must not be wrapped:
// WebSocket upgrades, HLS streaming, file/system endpoints.
func skipEnvelope(c *gin.Context) bool {
	if strings.EqualFold(c.GetHeader("Upgrade"), "websocket") {
		return true
	}
	p := c.Request.URL.Path
	switch {
	case p == "/health", p == "/metrics":
		return true
	case strings.HasPrefix(p, "/docs/"):
		return true
	case strings.HasPrefix(p, "/api/srs/"):
		// SRS HTTP-callback expects a bare "0"/"1" body, never JSON.
		return true
	case strings.Contains(p, "/hls/"):
		return true
	case strings.HasSuffix(p, ".m3u8") || strings.HasSuffix(p, ".ts"):
		return true
	case strings.Contains(p, "/ws/"):
		return true
	}
	return false
}

// bodyCapture buffers a handler's response so EnvelopeWrapper can re-emit
// it inside the envelope. It defers all writes to the real writer until
// the wrapper decides the final shape.
type bodyCapture struct {
	gin.ResponseWriter
	status   int
	buf      bytes.Buffer
	hijacked bool
}

func (w *bodyCapture) WriteHeader(code int) { w.status = code }

// WriteHeaderNow is a no-op: we don't flush the status to the socket until
// the wrapper has rebuilt the body. Gin calls this from c.Status/c.JSON.
func (w *bodyCapture) WriteHeaderNow() {}

func (w *bodyCapture) Write(b []byte) (int, error) {
	if w.status == 0 {
		w.status = http.StatusOK
	}
	return w.buf.Write(b)
}

func (w *bodyCapture) WriteString(s string) (int, error) {
	if w.status == 0 {
		w.status = http.StatusOK
	}
	return w.buf.WriteString(s)
}

func (w *bodyCapture) Status() int {
	if w.status == 0 {
		return http.StatusOK
	}
	return w.status
}

func (w *bodyCapture) Size() int { return w.buf.Len() }

func (w *bodyCapture) Written() bool { return w.status != 0 }

// Hijack delegates to the underlying writer (WebSocket upgrade) and marks
// the response so the wrapper leaves the hijacked connection alone.
func (w *bodyCapture) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	w.hijacked = true
	if hj, ok := w.ResponseWriter.(http.Hijacker); ok {
		return hj.Hijack()
	}
	return nil, nil, http.ErrNotSupported
}

// Flush is a no-op while buffering — streaming endpoints are excluded via
// skipEnvelope, so nothing relies on incremental flushes here.
func (w *bodyCapture) Flush() {}
