package handler

import (
	"encoding/json"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/cymed/layer/backend/internal/database"
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
	// schema_migrations が未作成でもエラーは無視してよい（MigrateSQL が作る）。
	_ = db.Exec("delete from schema_migrations where version = ?", "002_pin_location").Error
	if err := database.MigrateSQL(db); err != nil {
		t.Fatalf("migrate sql: %v", err)
	}
	return db
}

// 受け入れ基準: POST /api/pins で行が増え、GET /api/pins のレスポンスに
// lat/lng が含まれること。geography への往復で値が保たれることを確認する。
func TestPinHandler_CreateAndList(t *testing.T) {
	db := setupDB(t)
	h := NewPinHandler(db)
	e := echo.New()

	const (
		wantLat = 35.681236
		wantLng = 139.767125
	)
	body := `{"userId":"11111111-1111-1111-1111-111111111111","body":"いい場所","lat":35.681236,"lng":139.767125}`
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/pins", strings.NewReader(body))
	req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	if err := h.Create(e.NewContext(req, rec)); err != nil {
		t.Fatalf("Create: %v", err)
	}
	if rec.Code != http.StatusCreated {
		t.Fatalf("create status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var created pinResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode create: %v", err)
	}
	if created.ID == "" {
		t.Fatal("expected created id")
	}
	if created.CreatedAt.IsZero() {
		t.Fatal("expected createdAt to be set")
	}
	if !almostEqual(created.Lat, wantLat) || !almostEqual(created.Lng, wantLng) {
		t.Fatalf("create lat/lng = (%v,%v), want (%v,%v)", created.Lat, created.Lng, wantLat, wantLng)
	}

	rec = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/api/pins", nil)
	if err := h.List(e.NewContext(req, rec)); err != nil {
		t.Fatalf("List: %v", err)
	}
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
