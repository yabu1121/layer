package handler

import (
	"encoding/json"
	"math"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/cymed/layer/backend/internal/database"
	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// handler のテストは database パッケージの layer_test と衝突しないよう専用 DB を使う。
const (
	defaultHandlerDSN = "postgres://postgres:postgres@localhost:5432/layer_test_handler?sslmode=disable"
	defaultAdminDSN   = "postgres://postgres:postgres@localhost:5432/postgres?sslmode=disable"
	handlerDBName     = "layer_test_handler"
)

func TestMain(m *testing.M) {
	ensureDatabase(handlerDBName)
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

// setupDB は pins を作り直し、002 を再適用してまっさらな初期状態を返す。
// main.go と同じ AutoMigrate → MigrateSQL の順で適用する。
func setupDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsn := os.Getenv("TEST_HANDLER_DATABASE_URL")
	if dsn == "" {
		dsn = defaultHandlerDSN
	}
	db, err := gorm.Open(postgres.New(postgres.Config{DSN: dsn}), &gorm.Config{})
	if err != nil {
		t.Skipf("postgres unavailable: %v", err)
	}

	if err := db.Exec("drop table if exists pins cascade").Error; err != nil {
		t.Fatalf("drop pins: %v", err)
	}
	if err := database.Migrate(db); err != nil {
		t.Fatalf("automigrate: %v", err)
	}
	// 前回の記録が残っていると 002 が skip されるため、未適用に戻してから再適用する。
	// drop table pins cascade で pins 関連 FK（005 / comments の 006）も落ちるので
	// それらも再適用させる。schema_migrations が未作成でもエラーは無視してよい。
	_ = db.Exec("delete from schema_migrations where version in (?, ?, ?)",
		"002_pin_location", "005_foreign_keys", "006_comment_foreign_keys").Error
	if err := database.MigrateSQL(db); err != nil {
		t.Fatalf("migrate sql: %v", err)
	}
	return db
}

// authedPinEcho は auth ミドルウェア込みで Pin ルートを登録した echo を返す。
// 認証は authStubVerify（auth_test.go）で "good" -> "google-sub-1"。
func authedPinEcho(db *gorm.DB) *echo.Echo {
	e := echo.New()
	p := NewPinHandler(db)
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, authStubVerify))
	api.POST("/pins", p.Create)
	api.GET("/pins", p.List)
	api.GET("/pins/visible", p.ListVisible)
	api.GET("/pins/:id", p.Get)
	api.GET("/pins/:id/nearby", p.Nearby)
	return e
}

// seedPinUser は token "good" に対応する認証ユーザーを作る。
func seedPinUser(t *testing.T, db *gorm.DB, displayName, icon string) string {
	t.Helper()
	// FK 追加後（issue #47）は reactions / pin_discoveries も pins・users を参照するため cascade で消す。
	if err := db.Exec("truncate pins, users, friendships, notifications cascade").Error; err != nil {
		t.Fatalf("truncate: %v", err)
	}
	var id string
	if err := db.Raw(
		`insert into users (user_id, display_name, icon, auth_provider, auth_uid)
		 values ('me_user', ?, ?, 'google', 'google-sub-1') returning id`, displayName, icon,
	).Row().Scan(&id); err != nil {
		t.Fatalf("seed user: %v", err)
	}
	return id
}

// 受け入れ基準: POST /api/pins で行が増え、レスポンスに lat/lng と author が含まれ、
// GET /api/pins で取得できること。
func TestPinHandler_CreateAndList(t *testing.T) {
	db := setupDB(t)
	meID := seedPinUser(t, db, "Me", "🙂")
	e := authedPinEcho(db)

	const (
		wantLat = 35.681236
		wantLng = 139.767125
	)
	rec := serveAuth(e, http.MethodPost, "/api/pins", "good", `{"body":"いい場所","lat":35.681236,"lng":139.767125}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var created struct {
		Pin struct {
			ID        string    `json:"id"`
			UserID    string    `json:"userId"`
			Body      string    `json:"body"`
			Lat       float64   `json:"lat"`
			Lng       float64   `json:"lng"`
			CreatedAt time.Time `json:"createdAt"`
			Author    struct {
				ID          string `json:"id"`
				UserID      string `json:"userId"`
				DisplayName string `json:"displayName"`
				Icon        string `json:"icon"`
			} `json:"author"`
		} `json:"pin"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode create: %v", err)
	}
	if created.Pin.ID == "" {
		t.Fatal("expected created id")
	}
	if created.Pin.UserID != meID {
		t.Fatalf("pin userId = %q, want %q", created.Pin.UserID, meID)
	}
	if created.Pin.CreatedAt.IsZero() {
		t.Fatal("expected createdAt to be set")
	}
	if !almostEqual(created.Pin.Lat, wantLat) || !almostEqual(created.Pin.Lng, wantLng) {
		t.Fatalf("create lat/lng = (%v,%v), want (%v,%v)", created.Pin.Lat, created.Pin.Lng, wantLat, wantLng)
	}
	if created.Pin.Author.DisplayName != "Me" || created.Pin.Author.Icon != "🙂" {
		t.Fatalf("author = %+v, want Me/🙂", created.Pin.Author)
	}

	rec = serveAuth(e, http.MethodGet, "/api/pins", "good", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("list status = %d", rec.Code)
	}
	var list []pinResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil {
		t.Fatalf("decode list: %v", err)
	}
	if len(list) != 1 {
		t.Fatalf("expected 1 pin, got %d (%s)", len(list), rec.Body.String())
	}
	if !almostEqual(list[0].Lat, wantLat) || !almostEqual(list[0].Lng, wantLng) {
		t.Fatalf("list lat/lng = (%v,%v), want (%v,%v)", list[0].Lat, list[0].Lng, wantLat, wantLng)
	}
}

func TestPinCreate_Validation(t *testing.T) {
	db := setupDB(t)
	seedPinUser(t, db, "Me", "🙂")
	e := authedPinEcho(db)

	long := strings.Repeat("a", 201)
	cases := map[string]string{
		"empty body":       `{"body":"","lat":35.0,"lng":139.0}`,
		"whitespace body":  `{"body":"   ","lat":35.0,"lng":139.0}`,
		"too long body":    `{"body":"` + long + `","lat":35.0,"lng":139.0}`,
		"missing lat":      `{"body":"x","lng":139.0}`,
		"missing lng":      `{"body":"x","lat":35.0}`,
		"lat out of range": `{"body":"x","lat":91.0,"lng":139.0}`,
		"lng out of range": `{"body":"x","lat":35.0,"lng":181.0}`,
	}
	for name, b := range cases {
		t.Run(name, func(t *testing.T) {
			if rec := serveAuth(e, http.MethodPost, "/api/pins", "good", b); rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400 (%s)", rec.Code, rec.Body.String())
			}
		})
	}
}

func TestPinCreate_Unauthenticated401(t *testing.T) {
	db := setupDB(t)
	e := authedPinEcho(db)

	if rec := serveAuth(e, http.MethodPost, "/api/pins", "", `{"body":"x","lat":35.0,"lng":139.0}`); rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

// 受け入れ基準: location geography(Point,4326) が存在し lat/lng は無いこと、
// gist インデックスが存在すること。
func TestPinSchema_LocationColumnAndGistIndex(t *testing.T) {
	db := setupDB(t)

	var udtName string
	if err := db.Raw(
		`select udt_name from information_schema.columns where table_name = 'pins' and column_name = 'location'`,
	).Scan(&udtName).Error; err != nil || udtName != "geography" {
		t.Fatalf("location column udt_name = %q (err=%v), want \"geography\"", udtName, err)
	}

	for _, col := range []string{"lat", "lng"} {
		var cnt int64
		if err := db.Raw(
			`select count(*) from information_schema.columns where table_name = 'pins' and column_name = ?`, col,
		).Scan(&cnt).Error; err != nil {
			t.Fatalf("check column %s: %v", col, err)
		}
		if cnt != 0 {
			t.Fatalf("column %s should have been dropped", col)
		}
	}

	var idxCnt int64
	if err := db.Raw(
		`select count(*) from pg_indexes where tablename = 'pins' and indexdef ilike '%using gist%' and indexdef ilike '%location%'`,
	).Scan(&idxCnt).Error; err != nil {
		t.Fatalf("check gist index: %v", err)
	}
	if idxCnt == 0 {
		t.Fatal("gist index on location not found")
	}

	// created_at は model.md §2 どおり not null + default を持つ。
	var isNullable, def string
	if err := db.Raw(
		`select is_nullable, coalesce(column_default,'') from information_schema.columns where table_name = 'pins' and column_name = 'created_at'`,
	).Row().Scan(&isNullable, &def); err != nil {
		t.Fatalf("created_at meta: %v", err)
	}
	if isNullable != "NO" || def == "" {
		t.Fatalf("created_at is_nullable=%q default=%q, want NO + non-empty default", isNullable, def)
	}
}

func almostEqual(a, b float64) bool {
	return math.Abs(a-b) < 1e-6
}
