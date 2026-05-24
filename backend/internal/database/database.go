package database

import (
	"github.com/cymed/layer/backend/internal/model"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// Connect は PostgreSQL に接続する。
func Connect(dsn string) (*gorm.DB, error) {
	return gorm.Open(postgres.New(postgres.Config{DSN: dsn}), &gorm.Config{})
}

// Migrate はモデル定義に基づいてスキーマを自動マイグレーションする。
// PostGIS 拡張・地理空間インデックス・トリガーは SQL マイグレーションで別途管理する
// （docs/model/model.md を参照）。
func Migrate(db *gorm.DB) error {
	return db.AutoMigrate(
		&model.User{},
		&model.Friendship{},
		&model.Pin{},
		&model.Reaction{},
		&model.Comment{},
		&model.PinDiscovery{},
		&model.Notification{},
	)
}
