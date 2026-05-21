package middleware

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/cymed/layer/backend/internal/model"
	"github.com/labstack/echo/v4"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

const (
	defaultAuthDSN  = "postgres://postgres:postgres@localhost:5432/layer_test_authmw?sslmode=disable"
	defaultAdminDSN = "postgres://postgres:postgres@localhost:5432/postgres?sslmode=disable"
	authDBName      = "layer_test_authmw"
)

func TestMain(m *testing.M) {
	ensureDatabase(authDBName)
	os.Exit(m.Run())
}

func ensureDatabase(name string) {
	adminDSN := os.Getenv("TEST_ADMIN_DSN")
	if adminDSN == "" {
		adminDSN = defaultAdminDSN
	}
	admin, err := gorm.Open(postgres.New(postgres.Config{DSN: adminDSN}), &gorm.Config{})
	if err != nil {
		return
	}
	defer func() {
		if sqlDB, err := admin.DB(); err == nil {
			_ = sqlDB.Close()
		}
	}()
	var exists int64
	if err := admin.Raw("select count(*) from pg_database where datname = ?", name).Scan(&exists).Error; err != nil {
		return
	}
	if exists == 0 {
		_ = admin.Exec("create database " + name).Error
	}
}

func setupDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsn := os.Getenv("TEST_AUTH_DATABASE_URL")
	if dsn == "" {
		dsn = defaultAuthDSN
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

// stubVerify は token=="good" のときだけ固定の sub を返すスタブ。
func stubVerify(ctx context.Context, token string) (string, error) {
	if token == "good" {
		return "sub-123", nil
	}
	return "", errors.New("invalid token")
}

// guarded は RequireAuth を適用したテスト用エンドポイントを持つ echo を返す。
// ハンドラは CurrentUser の ID を本文に書き出すので、認証ユーザーの伝播も確認できる。
func guarded(db *gorm.DB) *echo.Echo {
	e := echo.New()
	h := func(c echo.Context) error {
		return c.String(http.StatusOK, CurrentUser(c).ID)
	}
	e.GET("/api/me", h, RequireAuth(db, stubVerify, "/api/auth/sign-in"))
	e.POST("/api/auth/sign-in", func(c echo.Context) error {
		return c.String(http.StatusOK, "public")
	}, RequireAuth(db, stubVerify, "/api/auth/sign-in"))
	return e
}

func do(e *echo.Echo, method, path, authHeader string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, nil)
	if authHeader != "" {
		req.Header.Set(echo.HeaderAuthorization, authHeader)
	}
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	return rec
}

func TestRequireAuth(t *testing.T) {
	db := setupDB(t)
	e := guarded(db)

	// 各サブテストは users の状態を自分で用意して独立させる。
	truncate := func(t *testing.T) {
		t.Helper()
		if err := db.Exec("truncate users").Error; err != nil {
			t.Fatalf("truncate: %v", err)
		}
	}
	seedAlice := func(t *testing.T) string {
		t.Helper()
		var id string
		if err := db.Raw(
			`insert into users (user_id, display_name, auth_provider, auth_uid)
			 values ('alice', 'Alice', 'google', 'sub-123') returning id`,
		).Row().Scan(&id); err != nil {
			t.Fatalf("seed user: %v", err)
		}
		return id
	}

	t.Run("no token is 401", func(t *testing.T) {
		truncate(t)
		if rec := do(e, http.MethodGet, "/api/me", ""); rec.Code != http.StatusUnauthorized {
			t.Fatalf("status = %d, want 401", rec.Code)
		}
	})

	t.Run("invalid token is 401", func(t *testing.T) {
		truncate(t)
		if rec := do(e, http.MethodGet, "/api/me", "Bearer bad"); rec.Code != http.StatusUnauthorized {
			t.Fatalf("status = %d, want 401", rec.Code)
		}
	})

	t.Run("valid token but unknown user is 401", func(t *testing.T) {
		truncate(t)
		if rec := do(e, http.MethodGet, "/api/me", "Bearer good"); rec.Code != http.StatusUnauthorized {
			t.Fatalf("status = %d, want 401", rec.Code)
		}
	})

	t.Run("valid token and known user is 200 with CurrentUser", func(t *testing.T) {
		truncate(t)
		id := seedAlice(t)
		rec := do(e, http.MethodGet, "/api/me", "Bearer good")
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
		}
		if rec.Body.String() != id {
			t.Fatalf("CurrentUser id = %q, want %q", rec.Body.String(), id)
		}
	})

	t.Run("public path is skipped without token", func(t *testing.T) {
		truncate(t)
		rec := do(e, http.MethodPost, "/api/auth/sign-in", "")
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200 (public)", rec.Code)
		}
	})
}
