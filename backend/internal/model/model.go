// Package model は DB テーブルに対応する構造体を定義する。
// スキーマの正は docs/model/model.md。変更時は両方を更新すること。
//
// 外部キー制約は association を定義していないため AutoMigrate では生成されない。
// model.md §2 の FK は SQL マイグレーション（migrations/005_foreign_keys.sql）で管理する。
package model

import "time"

// User はアカウント。
type User struct {
	ID           string    `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID       string    `gorm:"uniqueIndex;not null" json:"userId"` // 表示・検索用ハンドル
	DisplayName  string    `gorm:"not null" json:"displayName"`
	Icon         string    `json:"icon"`
	AuthProvider string    `gorm:"not null" json:"-"`
	AuthUID      string    `gorm:"uniqueIndex;not null" json:"-"`
	CreatedAt    time.Time `json:"createdAt"`
	// 現在地（点表示用）。未報告なら null。
	LastLat        *float64   `json:"lastLat,omitempty"`
	LastLng        *float64   `json:"lastLng,omitempty"`
	LastLocationAt *time.Time `json:"lastLocationAt,omitempty"`
}

// Friendship は友達関係（pending / accepted / rejected）。
type Friendship struct {
	ID          string     `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	RequesterID string     `gorm:"type:uuid;not null;uniqueIndex:idx_friend_pair" json:"requesterId"`
	ReceiverID  string     `gorm:"type:uuid;not null;uniqueIndex:idx_friend_pair" json:"receiverId"`
	Status      string     `gorm:"not null" json:"status"` // pending | accepted | rejected
	CreatedAt   time.Time  `json:"createdAt"`
	AcceptedAt  *time.Time `json:"acceptedAt,omitempty"`
}

// Pin は場所への投稿。
// 位置 location は PostGIS の geography(point,4326)。gorm の AutoMigrate では
// 扱えないため、location カラム・地理空間インデックス・発見検知トリガーは
// SQL マイグレーションで管理する（migrations/002_pin_location.sql, docs/model/model.md §2,§4）。
// API では handler が ST_X/ST_Y で lat/lng に展開して入出力する。
type Pin struct {
	ID        string    `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID    string    `gorm:"type:uuid;not null;index" json:"userId"`
	Body      string    `gorm:"not null" json:"body"`
	CreatedAt time.Time `json:"createdAt"`
}

// Reaction は「わかる」共感。
type Reaction struct {
	ID        string    `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	PinID     string    `gorm:"type:uuid;not null;index;uniqueIndex:idx_reaction" json:"pinId"`
	UserID    string    `gorm:"type:uuid;not null;index;uniqueIndex:idx_reaction" json:"userId"`
	Kind      string    `gorm:"not null;default:wakaru;uniqueIndex:idx_reaction" json:"kind"`
	CreatedAt time.Time `json:"createdAt"`
}

// PinDiscovery は発見ログ。
type PinDiscovery struct {
	ID          string    `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID      string    `gorm:"type:uuid;not null;index" json:"userId"`       // 発見した側
	PinID       string    `gorm:"type:uuid;not null" json:"pinId"`              // 発見された Pin
	TriggeredBy string    `gorm:"type:uuid;not null" json:"triggeredBy"`        // きっかけの Pin
	CreatedAt   time.Time `json:"createdAt"`
}

// Notification は in-app 通知。
type Notification struct {
	ID        string     `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID    string     `gorm:"type:uuid;not null;index" json:"userId"`
	Kind      string     `gorm:"not null" json:"kind"` // friend_request | friend_accepted | reaction | discovery
	Payload   string     `gorm:"type:jsonb;not null" json:"payload"`
	ReadAt    *time.Time `json:"readAt,omitempty"`
	CreatedAt time.Time  `json:"createdAt"`
}
