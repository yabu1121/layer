package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

// userEcho は auth ミドルウェア込みで検索ルートを登録した echo を返す。
// 認証は authStubVerify（auth_test.go）で "good" -> "google-sub-1"。
func userEcho(db *gorm.DB) *echo.Echo {
	e := echo.New()
	u := NewUserHandler(db)
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, authStubVerify))
	api.GET("/users/search", u.Search)
	return e
}

func seedSearchUser(t *testing.T, db *gorm.DB, userID, authUID, displayName, icon string) {
	t.Helper()
	if err := db.Exec(
		`insert into users (user_id, display_name, icon, auth_provider, auth_uid)
		 values (?, ?, ?, 'google', ?)`, userID, displayName, icon, authUID,
	).Error; err != nil {
		t.Fatalf("seed user %s: %v", userID, err)
	}
}

func search(e *echo.Echo, userID, token string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, "/api/users/search?user_id="+userID, nil)
	if token != "" {
		req.Header.Set(echo.HeaderAuthorization, "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	return rec
}

func TestUserSearch(t *testing.T) {
	db := setupAuthDB(t)
	// 認証ユーザー（自分）と検索対象。
	seedSearchUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	seedSearchUser(t, db, "alice_h", "other-sub", "Alice", "😀")
	e := userEcho(db)

	t.Run("existing user_id returns 200 with public profile", func(t *testing.T) {
		rec := search(e, "alice_h", "good")
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
		}
		var got userBody
		if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if got.User.UserID != "alice_h" || got.User.DisplayName != "Alice" || got.User.Icon != "😀" {
			t.Fatalf("public profile = %+v, want alice_h/Alice/😀", got.User)
		}

		// 公開プロフィールは created_at 等を露出しない（require.md §6.2）。
		var raw map[string]json.RawMessage
		if err := json.Unmarshal(rec.Body.Bytes(), &raw); err != nil {
			t.Fatalf("decode raw: %v", err)
		}
		var userMap map[string]any
		if err := json.Unmarshal(raw["user"], &userMap); err != nil {
			t.Fatalf("decode user: %v", err)
		}
		for _, hidden := range []string{"createdAt", "authProvider", "authUid"} {
			if _, ok := userMap[hidden]; ok {
				t.Fatalf("field %q should not be exposed in search result", hidden)
			}
		}
	})

	t.Run("self is returned", func(t *testing.T) {
		rec := search(e, "me_user", "good")
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200", rec.Code)
		}
		var got userBody
		_ = json.Unmarshal(rec.Body.Bytes(), &got)
		if got.User.UserID != "me_user" {
			t.Fatalf("userId = %q, want me_user", got.User.UserID)
		}
	})

	t.Run("unregistered user_id is 404", func(t *testing.T) {
		if rec := search(e, "nobody", "good"); rec.Code != http.StatusNotFound {
			t.Fatalf("status = %d, want 404", rec.Code)
		}
	})

	t.Run("partial match is 404", func(t *testing.T) {
		if rec := search(e, "alice", "good"); rec.Code != http.StatusNotFound {
			t.Fatalf("status = %d, want 404 (partial must not match)", rec.Code)
		}
	})

	t.Run("prefix match is 404", func(t *testing.T) {
		if rec := search(e, "alice_", "good"); rec.Code != http.StatusNotFound {
			t.Fatalf("status = %d, want 404 (prefix must not match)", rec.Code)
		}
	})

	t.Run("missing user_id is 400", func(t *testing.T) {
		if rec := search(e, "", "good"); rec.Code != http.StatusBadRequest {
			t.Fatalf("status = %d, want 400", rec.Code)
		}
	})

	t.Run("unauthenticated is 401", func(t *testing.T) {
		if rec := search(e, "alice_h", ""); rec.Code != http.StatusUnauthorized {
			t.Fatalf("status = %d, want 401", rec.Code)
		}
	})
}

type userBody struct {
	User struct {
		UserID      string `json:"userId"`
		DisplayName string `json:"displayName"`
		Icon        string `json:"icon"`
	} `json:"user"`
}
