package handler

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/labstack/echo/v4"
)

func TestReady_OKWhenDBUp(t *testing.T) {
	db := setupDB(t)
	e := echo.New()
	e.GET("/ready", NewReadinessHandler(db).Ready)

	req := httptest.NewRequest(http.MethodGet, "/ready", nil)
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
}

func TestReady_503WhenDBDown(t *testing.T) {
	db := setupDB(t)
	// 接続プールを閉じて ping を失敗させる。
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("db handle: %v", err)
	}
	_ = sqlDB.Close()

	e := echo.New()
	e.GET("/ready", NewReadinessHandler(db).Ready)
	req := httptest.NewRequest(http.MethodGet, "/ready", nil)
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", rec.Code)
	}
}

func TestHealth_AlwaysOK(t *testing.T) {
	e := echo.New()
	e.GET("/health", Health)
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
}
