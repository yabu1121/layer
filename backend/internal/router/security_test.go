package router

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/labstack/echo/v4"
)

// testVerify は認証検証のスタブ（token をそのまま subject とする）。
func testVerify(_ context.Context, token string) (string, error) { return token, nil }

func TestSecurity_CORSRestrictsToAllowedOrigins(t *testing.T) {
	t.Setenv("ALLOWED_ORIGINS", "https://app.example.com")
	e := New(nil, testVerify)

	// 許可オリジン → Allow-Origin が反映される。
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set(echo.HeaderOrigin, "https://app.example.com")
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	if got := rec.Header().Get(echo.HeaderAccessControlAllowOrigin); got != "https://app.example.com" {
		t.Fatalf("allow-origin = %q, want https://app.example.com", got)
	}

	// 許可外オリジン → Allow-Origin が付かない。
	req2 := httptest.NewRequest(http.MethodGet, "/health", nil)
	req2.Header.Set(echo.HeaderOrigin, "https://evil.com")
	rec2 := httptest.NewRecorder()
	e.ServeHTTP(rec2, req2)
	if got := rec2.Header().Get(echo.HeaderAccessControlAllowOrigin); got != "" {
		t.Fatalf("allow-origin = %q, want empty for disallowed origin", got)
	}
}

func TestSecurity_CORSDefaultsToWildcardWhenUnset(t *testing.T) {
	t.Setenv("ALLOWED_ORIGINS", "")
	e := New(nil, testVerify)

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set(echo.HeaderOrigin, "https://anything.example")
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	if got := rec.Header().Get(echo.HeaderAccessControlAllowOrigin); got != "*" {
		t.Fatalf("allow-origin = %q, want * (dev default)", got)
	}
}

func TestSecurity_SecureHeaders(t *testing.T) {
	e := New(nil, testVerify)
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	if got := rec.Header().Get(echo.HeaderXContentTypeOptions); got != "nosniff" {
		t.Fatalf("X-Content-Type-Options = %q, want nosniff", got)
	}
}

func TestSecurity_BodyLimitRejectsLarge(t *testing.T) {
	e := New(nil, testVerify)
	big := strings.Repeat("a", 2*1024*1024) // 2MB > 1MB 上限
	req := httptest.NewRequest(http.MethodPost, "/health", strings.NewReader(big))
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want 413", rec.Code)
	}
}
