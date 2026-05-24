package router

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRateLimit_Returns429WhenExceeded(t *testing.T) {
	// 1 rps / burst 1 にして 2 連打で超過させる。
	t.Setenv("RATE_LIMIT_RPS", "1")
	t.Setenv("RATE_LIMIT_BURST", "1")
	e := New(nil, testVerify)

	// 1 回目はレート制限を通過する（トークン無しで 401 になるが 429 ではない）。
	rec1 := httptest.NewRecorder()
	e.ServeHTTP(rec1, httptest.NewRequest(http.MethodGet, "/api/me", nil))
	if rec1.Code == http.StatusTooManyRequests {
		t.Fatalf("1st request should not be rate-limited, got 429")
	}

	// 2 回目（同一 IP・即時）はレート超過で 429。
	rec2 := httptest.NewRecorder()
	e.ServeHTTP(rec2, httptest.NewRequest(http.MethodGet, "/api/me", nil))
	if rec2.Code != http.StatusTooManyRequests {
		t.Fatalf("2nd request status = %d, want 429", rec2.Code)
	}
}

func TestRateLimit_AllowsWithinLimit(t *testing.T) {
	t.Setenv("RATE_LIMIT_RPS", "100")
	t.Setenv("RATE_LIMIT_BURST", "100")
	e := New(nil, testVerify)

	for i := 0; i < 5; i++ {
		rec := httptest.NewRecorder()
		e.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("/health request %d status = %d, want 200", i, rec.Code)
		}
	}
}
