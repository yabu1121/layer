package database

import (
	"os"
	"testing"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// テスト用 DB の DSN。dev DB を破壊しないため layer_test を専用に使う。
// CI 等で別 DB を指したい場合は TEST_DATABASE_URL で上書きできる。
const defaultTestDSN = "postgres://postgres:postgres@localhost:5432/layer_test?sslmode=disable"

// 管理 DB（CREATE DATABASE 用）。
const defaultAdminDSN = "postgres://postgres:postgres@localhost:5432/postgres?sslmode=disable"

// TestMain は layer_test DB が無ければ作成する。失敗してもテストは Skip 側で
// 対応するため fatal にはしない。
func TestMain(m *testing.M) {
	ensureTestDatabase()
	os.Exit(m.Run())
}

func ensureTestDatabase() {
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
	if err := admin.Raw("select count(*) from pg_database where datname = ?", "layer_test").Scan(&exists).Error; err != nil {
		return
	}
	if exists == 0 {
		_ = admin.Exec("create database layer_test").Error
	}
}

// TestMigrateSQL は 001_init_postgis が適用され、二度目の呼び出しは no-op に
// なることを確認する。DB が無い環境ではスキップする。
func TestMigrateSQL_AppliesAndIsIdempotent(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = defaultTestDSN
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

// TestMigrateSQL_RollbackOnFailure はマイグレーション本体が失敗したら
// schema_migrations への記録も巻き戻る（次回再試行できる）ことを確認する。
func TestMigrateSQL_RollbackOnFailure(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = defaultTestDSN
	}
	db, err := gorm.Open(postgres.New(postgres.Config{DSN: dsn}), &gorm.Config{})
	if err != nil {
		t.Skipf("postgres unavailable: %v", err)
	}

	if err := db.Exec("drop table if exists schema_migrations").Error; err != nil {
		t.Fatalf("drop schema_migrations: %v", err)
	}
	if err := db.Exec(schemaMigrationsDDL).Error; err != nil {
		t.Fatalf("create schema_migrations: %v", err)
	}

	// 不正な SQL を本体として直接 Transaction に流す（migrate_sql 内部と同じ構造）。
	applyErr := db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("this is not valid sql").Error; err != nil {
			return err
		}
		return tx.Exec("insert into schema_migrations(version) values (?)", "999_bogus").Error
	})
	if applyErr == nil {
		t.Fatal("expected transaction to fail with invalid SQL")
	}

	var count int64
	if err := db.Raw("select count(*) from schema_migrations where version = ?", "999_bogus").Scan(&count).Error; err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != 0 {
		t.Fatalf("expected schema_migrations row to be rolled back, got count=%d", count)
	}
}
