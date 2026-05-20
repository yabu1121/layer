package database

import (
	"os"
	"testing"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// TestMigrateSQL は 001_init_postgis が適用され、二度目の呼び出しは no-op に
// なることを確認する。DB が無い環境ではスキップする。
func TestMigrateSQL_AppliesAndIsIdempotent(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://postgres:postgres@localhost:5432/layer?sslmode=disable"
	}
	db, err := gorm.Open(postgres.New(postgres.Config{DSN: dsn}), &gorm.Config{})
	if err != nil {
		t.Skipf("postgres unavailable: %v", err)
	}

	if err := db.Exec("drop table if exists schema_migrations").Error; err != nil {
		t.Fatalf("drop schema_migrations: %v", err)
	}

	if err := MigrateSQL(db); err != nil {
		t.Fatalf("first MigrateSQL: %v", err)
	}

	var version string
	if err := db.Raw("select version from schema_migrations where version = ?", "001_init_postgis").Scan(&version).Error; err != nil {
		t.Fatalf("query schema_migrations: %v", err)
	}
	if version != "001_init_postgis" {
		t.Fatalf("expected 001_init_postgis applied, got %q", version)
	}

	var postgisVersion string
	if err := db.Raw("select postgis_version()").Scan(&postgisVersion).Error; err != nil {
		t.Fatalf("postgis_version: %v", err)
	}
	if postgisVersion == "" {
		t.Fatal("postgis_version() returned empty")
	}

	if err := MigrateSQL(db); err != nil {
		t.Fatalf("second MigrateSQL: %v", err)
	}
	var count int64
	if err := db.Raw("select count(*) from schema_migrations").Scan(&count).Error; err != nil {
		t.Fatalf("count schema_migrations: %v", err)
	}
	if count != 1 {
		t.Fatalf("expected 1 row in schema_migrations, got %d", count)
	}
}
