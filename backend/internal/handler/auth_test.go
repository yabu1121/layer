package handler

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/cymed/layer/backend/internal/model"
	"github.com/labstack/echo/v4"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// TestMain / defaultHandlerDSN は pin_test.go（同パッケージ）で定義済み。
func setupAuthDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsn := os.Getenv("TEST_HANDLER_DATABASE_URL")
	if dsn == "" {
		dsn = defaultHandlerDSN
	}
	db, err := gorm.Open(postgres.New(postgres.Config{DSN: dsn}), &gorm.Config{})
	if err != nil {
		t.Skipf("postgres unavailable: %v", err)
	}
	if err := db.AutoMigrate(&model.User{}); err != nil {
		t.Fatalf("automigrate: %v", err)
	}
	if err := db.Exec("truncate users").Error; err != nil {
		t.Fatalf("truncate: %v", err)
	}
	return db
}

func authStubVerify(_ context.Context, token string) (string, error) {
	if token == "good" {
		return "google-sub-1", nil
	}
	return "", errors.New("invalid token")
}

func authEcho(db *gorm.DB) *echo.Echo {
	h := NewAuthHandler(db, authStubVerify)
	e := echo.New()
	e.POST("/api/auth/sign-in", h.SignIn)
	e.POST("/api/auth/sign-out", h.SignOut)
	return e
}

func serve(e *echo.Echo, method, path, body string) *httptest.ResponseRecorder {
	var r io.Reader
	if body != "" {
		r = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, path, r)
	req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	return rec
}

type signInBody struct {
	User struct {
		ID     string `json:"id"`
		UserID string `json:"userId"`
	} `json:"user"`
	IsNew bool `json:"is_new"`
}

func TestSignIn_NewUserIsCreated(t *testing.T) {
	db := setupAuthDB(t)
	e := authEcho(db)

	rec := serve(e, http.MethodPost, "/api/auth/sign-in", `{"id_token":"good"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	var got signInBody
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if !got.IsNew {
		t.Fatal("is_new = false, want true for first sign-in")
	}
	if got.User.ID == "" {
		t.Fatal("expected created user id")
	}
	if !strings.HasPrefix(got.User.UserID, "user_") {
		t.Fatalf("userId = %q, want user_ prefix", got.User.UserID)
	}
	var count int64
	if err := db.Raw(`select count(*) from users where auth_uid = ?`, "google-sub-1").Scan(&count).Error; err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != 1 {
		t.Fatalf("users rows = %d, want 1", count)
	}
}

func TestSignIn_ExistingUserIsReused(t *testing.T) {
	db := setupAuthDB(t)
	e := authEcho(db)

	first := serve(e, http.MethodPost, "/api/auth/sign-in", `{"id_token":"good"}`)
	var a signInBody
	if err := json.Unmarshal(first.Body.Bytes(), &a); err != nil {
		t.Fatalf("decode first: %v", err)
	}

	second := serve(e, http.MethodPost, "/api/auth/sign-in", `{"id_token":"good"}`)
	if second.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", second.Code)
	}
	var b signInBody
	if err := json.Unmarshal(second.Body.Bytes(), &b); err != nil {
		t.Fatalf("decode second: %v", err)
	}
	if b.IsNew {
		t.Fatal("is_new = true on re-sign-in, want false")
	}
	if b.User.ID != a.User.ID {
		t.Fatalf("user id changed: %q -> %q", a.User.ID, b.User.ID)
	}
	var count int64
	if err := db.Raw(`select count(*) from users`).Scan(&count).Error; err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != 1 {
		t.Fatalf("users rows = %d, want 1 (no duplicate)", count)
	}
}

func TestSignIn_InvalidTokenIs401(t *testing.T) {
	db := setupAuthDB(t)
	e := authEcho(db)

	rec := serve(e, http.MethodPost, "/api/auth/sign-in", `{"id_token":"bad"}`)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func TestSignOut_Is204(t *testing.T) {
	db := setupAuthDB(t)
	e := authEcho(db)

	rec := serve(e, http.MethodPost, "/api/auth/sign-out", "")
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
}

// #2: user_id が衝突したら採番し直して成功する。
func TestSignIn_UserIDCollisionRetries(t *testing.T) {
	db := setupAuthDB(t)
	if err := db.Exec(
		`insert into users (user_id, display_name, auth_provider, auth_uid)
		 values ('user_dup', '', 'google', 'other-sub')`,
	).Error; err != nil {
		t.Fatalf("seed: %v", err)
	}
	h := NewAuthHandler(db, authStubVerify) // "good" -> "google-sub-1"
	calls := 0
	h.newUserID = func() string {
		calls++
		if calls == 1 {
			return "user_dup" // 1 回目は既存と衝突
		}
		return "user_ok"
	}
	e := echo.New()
	e.POST("/api/auth/sign-in", h.SignIn)

	rec := serve(e, http.MethodPost, "/api/auth/sign-in", `{"id_token":"good"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	var got signInBody
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if !got.IsNew {
		t.Fatal("is_new = false, want true")
	}
	if got.User.UserID != "user_ok" {
		t.Fatalf("userId = %q, want user_ok (after retry)", got.User.UserID)
	}
	if calls < 2 {
		t.Fatalf("newUserID called %d times, want >= 2 (retry expected)", calls)
	}
}

// #1: First の後・Create の前に同じ auth_uid が並行作成された場合、500 ではなく
// 既存ユーザーを is_new=false で返す。newUserID フックで競合を再現する。
func TestSignIn_ConcurrentCreateFallsBackToExisting(t *testing.T) {
	db := setupAuthDB(t)
	h := NewAuthHandler(db, authStubVerify) // "good" -> "google-sub-1"
	h.newUserID = func() string {
		// 並行サインインを模して、同じ auth_uid の行を先に作る。
		_ = db.Exec(
			`insert into users (user_id, display_name, auth_provider, auth_uid)
			 values ('user_concurrent', '', 'google', 'google-sub-1') on conflict do nothing`,
		).Error
		return "user_self"
	}
	e := echo.New()
	e.POST("/api/auth/sign-in", h.SignIn)

	rec := serve(e, http.MethodPost, "/api/auth/sign-in", `{"id_token":"good"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	var got signInBody
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got.IsNew {
		t.Fatal("is_new = true, want false (existing user on race)")
	}
	if got.User.UserID != "user_concurrent" {
		t.Fatalf("userId = %q, want user_concurrent", got.User.UserID)
	}
	var count int64
	if err := db.Raw(`select count(*) from users where auth_uid = ?`, "google-sub-1").Scan(&count).Error; err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != 1 {
		t.Fatalf("users with auth_uid = %d, want 1 (no duplicate)", count)
	}
}
