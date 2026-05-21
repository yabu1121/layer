package database

import (
	"os"
	"strings"
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

// TestMigrateSQL は migrations/ 配下が全て適用され、二度目の呼び出しは no-op に
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

	// 002 以降は pins テーブルの存在を前提とする。本番は AutoMigrate → MigrateSQL の
	// 順で走るため、テストでも同じ順序を再現する。
	if err := Migrate(db); err != nil {
		t.Fatalf("AutoMigrate: %v", err)
	}

	if err := MigrateSQL(db); err != nil {
		t.Fatalf("first MigrateSQL: %v", err)
	}

	// migrations/ の全ファイルが記録されている。
	names, err := listMigrations()
	if err != nil {
		t.Fatalf("listMigrations: %v", err)
	}
	for _, name := range names {
		version := strings.TrimSuffix(name, ".sql")
		var got string
		if err := db.Raw("select version from schema_migrations where version = ?", version).Scan(&got).Error; err != nil || got != version {
			t.Fatalf("migration %q not recorded (got %q, err=%v)", version, got, err)
		}
	}

	// 001: PostGIS 拡張が有効。
	var postgisVersion string
	if err := db.Raw("select postgis_version()").Scan(&postgisVersion).Error; err != nil {
		t.Fatalf("postgis_version: %v", err)
	}
	if postgisVersion == "" {
		t.Fatal("postgis_version() returned empty")
	}

	// 002: pins.location が geography で存在する。
	var udtName string
	if err := db.Raw("select udt_name from information_schema.columns where table_name = 'pins' and column_name = 'location'").Scan(&udtName).Error; err != nil || udtName != "geography" {
		t.Fatalf("pins.location udt_name = %q (err=%v), want \"geography\"", udtName, err)
	}

	// 二度目は no-op（行数が増えず、ファイル数と一致する）。
	if err := MigrateSQL(db); err != nil {
		t.Fatalf("second MigrateSQL: %v", err)
	}
	var count int64
	if err := db.Raw("select count(*) from schema_migrations").Scan(&count).Error; err != nil {
		t.Fatalf("count schema_migrations: %v", err)
	}
	if count != int64(len(names)) {
		t.Fatalf("expected %d rows in schema_migrations, got %d", len(names), count)
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
