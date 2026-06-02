package httpx

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() { gin.SetMode(gin.TestMode) }

func newWrapped() *gin.Engine {
	r := gin.New()
	r.Use(EnvelopeWrapper())
	r.Use(ErrorHandler(slog.New(slog.NewTextHandler(io.Discard, nil))))
	return r
}

func do(r *gin.Engine, method, path string) (*httptest.ResponseRecorder, Envelope) {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(method, path, nil)
	r.ServeHTTP(w, req)
	var env Envelope
	_ = json.Unmarshal(w.Body.Bytes(), &env)
	return w, env
}

func TestEnvelope_Success(t *testing.T) {
	r := newWrapped()
	r.GET("/ok", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"foo": "bar"})
	})
	w, env := do(r, "GET", "/ok")
	if w.Code != 200 {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	if !env.Result || env.StatusCode != "200" || env.Status != 200 {
		t.Fatalf("bad envelope: %+v", env)
	}
	data, ok := env.Data.(map[string]any)
	if !ok || data["foo"] != "bar" {
		t.Fatalf("data not preserved: %+v", env.Data)
	}
}

func TestEnvelope_HandlerMessage(t *testing.T) {
	r := newWrapped()
	r.GET("/login", func(c *gin.Context) {
		SetMessage(c, "Đăng nhập thành công")
		c.JSON(http.StatusOK, gin.H{"token": "abc"})
	})
	_, env := do(r, "GET", "/login")
	if env.Message != "Đăng nhập thành công" || env.StatusMess != "Đăng nhập thành công" {
		t.Fatalf("message not lifted: %+v", env)
	}
}

func TestEnvelope_Error(t *testing.T) {
	r := newWrapped()
	r.GET("/bad", func(c *gin.Context) {
		c.Error(NewNotFound("Stream không live hoặc không tồn tại"))
	})
	w, env := do(r, "GET", "/bad")
	if w.Code != 404 {
		t.Fatalf("status = %d, want 404", w.Code)
	}
	if env.Result || env.StatusCode != "404" || env.Data != nil {
		t.Fatalf("error envelope wrong: %+v", env)
	}
	if env.Message != "Stream không live hoặc không tồn tại" {
		t.Fatalf("error message not lifted: %q", env.Message)
	}
}

func TestEnvelope_NoContent(t *testing.T) {
	r := newWrapped()
	r.GET("/empty", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})
	_, env := do(r, "GET", "/empty")
	// 204 has no body → wrapper emits an envelope with null data. Result
	// stays true (2xx class).
	if !env.Result || env.Data != nil {
		t.Fatalf("no-content envelope wrong: %+v", env)
	}
}

func TestEnvelope_SkipPaths(t *testing.T) {
	r := newWrapped()
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"ok": true})
	})
	w, _ := do(r, "GET", "/health")
	var raw map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &raw); err != nil {
		t.Fatal(err)
	}
	if _, wrapped := raw["Result"]; wrapped {
		t.Fatalf("/health should not be enveloped: %s", w.Body.String())
	}
}
