package database

import (
	"embed"
	"fmt"
	"io/fs"
	"sort"
	"strings"

	"gorm.io/gorm"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

// schemaMigrationsDDL は適用済みマイグレーションを記録するテーブルの DDL。
const schemaMigrationsDDL = `create table if not exists schema_migrations (
  version    text primary key,
  applied_at timestamptz not null default now()
)`

// MigrateSQL は migrations/ 配下の .sql をファイル名順で未適用のみ実行する。
// 各 .sql は version = ファイル名から拡張子を除いた値で schema_migrations に記録する。
func MigrateSQL(db *gorm.DB) error {
	if err := db.Exec(schemaMigrationsDDL).Error; err != nil {
		return fmt.Errorf("create schema_migrations: %w", err)
	}

	names, err := listMigrations()
	if err != nil {
		return err
	}

	for _, name := range names {
		version := strings.TrimSuffix(name, ".sql")
		applied, err := isApplied(db, version)
		if err != nil {
			return err
		}
		if applied {
			continue
		}
		body, err := migrationsFS.ReadFile("migrations/" + name)
		if err != nil {
			return fmt.Errorf("read %s: %w", name, err)
		}
		// 本体実行と schema_migrations への記録は 1 トランザクションで完結させる。
		// 途中で失敗したら DB は変更前に戻り、再起動で同じ migration を最初からやり直せる。
		if err := db.Transaction(func(tx *gorm.DB) error {
			if err := tx.Exec(string(body)).Error; err != nil {
				return fmt.Errorf("apply %s: %w", name, err)
			}
			if err := tx.Exec("insert into schema_migrations(version) values (?)", version).Error; err != nil {
				return fmt.Errorf("record %s: %w", name, err)
			}
			return nil
		}); err != nil {
			return err
		}
	}
	return nil
}

func listMigrations() ([]string, error) {
	entries, err := fs.ReadDir(migrationsFS, "migrations")
	if err != nil {
		return nil, fmt.Errorf("read migrations dir: %w", err)
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".sql") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	return names, nil
}

func isApplied(db *gorm.DB, version string) (bool, error) {
	var count int64
	if err := db.Raw("select count(*) from schema_migrations where version = ?", version).Scan(&count).Error; err != nil {
		return false, fmt.Errorf("check %s: %w", version, err)
	}
	return count > 0, nil
}
