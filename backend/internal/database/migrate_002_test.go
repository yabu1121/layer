package database

import (
	"math"
	"os"
	"testing"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// TestMigration002_BackfillsLocationFromLatLng は、旧スキーマ（lat/lng カラム）に
// データがある状態で 002 を適用すると、location へ保全移送され、lat/lng は削除され、
// created_at が not null + default になることを確認する（レビュー指摘 #1, #2）。
func TestMigration002_BackfillsLocationFromLatLng(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = defaultTestDSN
	}
	db, err := gorm.Open(postgres.New(postgres.Config{DSN: dsn}), &gorm.Config{})
	if err != nil {
		t.Skipf("postgres unavailable: %v", err)
	}

	if err := db.Exec("create extension if not exists postgis").Error; err != nil {
		t.Fatalf("postgis: %v", err)
	}

	// 旧スキーマ（lat/lng あり・location なし・created_at は default なし nullable）を再現。
	if err := db.Exec("drop table if exists pins cascade").Error; err != nil {
		t.Fatalf("drop pins: %v", err)
	}
	if err := db.Exec(`create table pins (
		id         uuid primary key default gen_random_uuid(),
		user_id    uuid not null,
		body       text not null,
		lat        double precision,
		lng        double precision,
		created_at timestamptz
	)`).Error; err != nil {
		t.Fatalf("create old pins: %v", err)
	}
	// created_at を null のまま挿入し、移行で埋められ not null 化されることも確認する。
	const (
		wantLat = 35.681236
		wantLng = 139.767125
	)
	if err := db.Exec(
		`insert into pins (user_id, body, lat, lng, created_at) values (gen_random_uuid(), ?, ?, ?, null)`,
		"渋谷の夕暮れ", wantLat, wantLng,
	).Error; err != nil {
		t.Fatalf("insert old row: %v", err)
	}

	body, err := os.ReadFile("migrations/002_pin_location.sql")
	if err != nil {
		t.Fatalf("read migration: %v", err)
	}
	if err := db.Exec(string(body)).Error; err != nil {
		t.Fatalf("apply 002: %v", err)
	}

	// #1: location に保全移送されている。
	var lat, lng float64
	if err := db.Raw(`select st_y(location::geometry), st_x(location::geometry) from pins`).Row().Scan(&lat, &lng); err != nil {
		t.Fatalf("read location: %v", err)
	}
	if math.Abs(lat-wantLat) > 1e-6 || math.Abs(lng-wantLng) > 1e-6 {
		t.Fatalf("backfilled location = (%v,%v), want (%v,%v)", lat, lng, wantLat, wantLng)
	}

	// #1: lat/lng カラムは削除されている。
	for _, col := range []string{"lat", "lng"} {
		var cnt int64
		if err := db.Raw(`select count(*) from information_schema.columns where table_name='pins' and column_name=?`, col).Scan(&cnt).Error; err != nil {
			t.Fatalf("check column %s: %v", col, err)
		}
		if cnt != 0 {
			t.Fatalf("column %s should have been dropped", col)
		}
	}

	// #2: created_at が not null + default を持ち、既存の null 行も埋まっている。
	var isNullable, def string
	if err := db.Raw(`select is_nullable, coalesce(column_default,'') from information_schema.columns where table_name='pins' and column_name='created_at'`).Row().Scan(&isNullable, &def); err != nil {
		t.Fatalf("created_at meta: %v", err)
	}
	if isNullable != "NO" || def == "" {
		t.Fatalf("created_at is_nullable=%q default=%q, want NO + non-empty default", isNullable, def)
	}
	var nullCnt int64
	if err := db.Raw(`select count(*) from pins where created_at is null`).Scan(&nullCnt).Error; err != nil {
		t.Fatalf("count null created_at: %v", err)
	}
	if nullCnt != 0 {
		t.Fatalf("expected created_at backfilled, got %d nulls", nullCnt)
	}
}
