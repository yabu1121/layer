package handler

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

// meEcho は auth ミドルウェア込みで /api/me 系を登録した echo を返す。
// 認証は authStubVerify（auth_test.go）で "good" -> "google-sub-1"。
func meEcho(db *gorm.DB) *echo.Echo {
	e := echo.New()
	me := NewMeHandler(db)
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, authStubVerify))
	api.GET("/me", me.Get)
	api.POST("/me/profile", me.UpdateProfile)
	return e
}

// seedMe は token "good" の sub に対応する認証ユーザーを作る。
func seedMe(t *testing.T, db *gorm.DB, userID string) {
	t.Helper()
	if err := db.Exec(
		`insert into users (user_id, display_name, auth_provider, auth_uid)
		 values (?, '', 'google', 'google-sub-1')`, userID,
	).Error; err != nil {
		t.Fatalf("seed me: %v", err)
	}
}

func serveAuth(e *echo.Echo, method, path, token, body string) *httptest.ResponseRecorder {
	var r io.Reader
	if body != "" {
		r = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, path, r)
	req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	if token != "" {
		req.Header.Set(echo.HeaderAuthorization, "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	return rec
}

func TestMe_GetReturnsCurrentUser(t *testing.T) {
	db := setupAuthDB(t)
	seedMe(t, db, "me_user")
	e := meEcho(db)

	rec := serveAuth(e, http.MethodGet, "/api/me", "good", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	var got meBody
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got.User.UserID != "me_user" {
		t.Fatalf("userId = %q, want me_user", got.User.UserID)
	}
}

func TestMe_UpdateProfilePersists(t *testing.T) {
	db := setupAuthDB(t)
	seedMe(t, db, "me_user")
	e := meEcho(db)

	rec := serveAuth(e, http.MethodPost, "/api/me/profile", "good",
		`{"display_name":"りよ","icon":"😀","user_id":"riyo_1234"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}

	// 再取得して永続化を確認する。
	rec = serveAuth(e, http.MethodGet, "/api/me", "good", "")
	var got meBody
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got.User.UserID != "riyo_1234" || got.User.DisplayName != "りよ" || got.User.Icon != "😀" {
		t.Fatalf("persisted = %+v, want riyo_1234/りよ/😀", got.User)
	}
}

func TestMe_UpdateProfileTrimsWhitespace(t *testing.T) {
	db := setupAuthDB(t)
	seedMe(t, db, "me_user")
	e := meEcho(db)

	rec := serveAuth(e, http.MethodPost, "/api/me/profile", "good",
		`{"display_name":"  りよ  ","icon":" 😀 ","user_id":"riyo_1234"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	var got meBody
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got.User.DisplayName != "りよ" || got.User.Icon != "😀" {
		t.Fatalf("trimmed = %q/%q, want りよ/😀", got.User.DisplayName, got.User.Icon)
	}
}

func TestMe_UpdateProfileValidation(t *testing.T) {
	db := setupAuthDB(t)
	seedMe(t, db, "me_user")
	e := meEcho(db)

	cases := map[string]string{
		"empty display_name":      `{"display_name":"","icon":"😀","user_id":"riyo_1234"}`,
		"whitespace display_name": `{"display_name":"   ","icon":"😀","user_id":"riyo_1234"}`,
		"too long name":           `{"display_name":"012345678901234567890","icon":"😀","user_id":"riyo_1234"}`,
		"missing icon":            `{"display_name":"りよ","icon":"","user_id":"riyo_1234"}`,
		"plain text icon":         `{"display_name":"りよ","icon":"ab","user_id":"riyo_1234"}`,
		"too long icon":           `{"display_name":"りよ","icon":"😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀","user_id":"riyo_1234"}`,
		"bad user_id":             `{"display_name":"りよ","icon":"😀","user_id":"ab"}`,
		"user_id with space":      `{"display_name":"りよ","icon":"😀","user_id":"ri yo"}`,
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			rec := serveAuth(e, http.MethodPost, "/api/me/profile", "good", body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400 (%s)", rec.Code, rec.Body.String())
			}
		})
	}
}

func TestMe_UpdateProfileDuplicateUserID(t *testing.T) {
	db := setupAuthDB(t)
	seedMe(t, db, "me_user")
	// 別ユーザーが "taken_id" を既に使用。
	if err := db.Exec(
		`insert into users (user_id, display_name, auth_provider, auth_uid)
		 values ('taken_id', 'Other', 'google', 'other-sub')`,
	).Error; err != nil {
		t.Fatalf("seed other: %v", err)
	}
	e := meEcho(db)

	rec := serveAuth(e, http.MethodPost, "/api/me/profile", "good",
		`{"display_name":"りよ","icon":"😀","user_id":"taken_id"}`)
	if rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409 (%s)", rec.Code, rec.Body.String())
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body["error"] != "user_id_taken" {
		t.Fatalf("error = %q, want user_id_taken", body["error"])
	}
}

func TestMe_Unauthenticated401(t *testing.T) {
	db := setupAuthDB(t)
	e := meEcho(db)

	if rec := serveAuth(e, http.MethodGet, "/api/me", "", ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("GET status = %d, want 401", rec.Code)
	}
	if rec := serveAuth(e, http.MethodPost, "/api/me/profile", "",
		`{"display_name":"りよ","icon":"😀","user_id":"riyo_1234"}`); rec.Code != http.StatusUnauthorized {
		t.Fatalf("POST status = %d, want 401", rec.Code)
	}
}

type meBody struct {
	User struct {
		UserID      string `json:"userId"`
		DisplayName string `json:"displayName"`
		Icon        string `json:"icon"`
	} `json:"user"`
}
