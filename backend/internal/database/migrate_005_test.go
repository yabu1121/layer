package database

import (
	"os"
	"testing"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// expectedForeignKeys は docs/model/model.md §2 が定義する全外部キー。
// confDelType は pg_constraint.confdeltype（a=no action, c=cascade）。
// cascade は model.md が明記する reactions.pin_id のみ。
var expectedForeignKeys = []struct {
	name        string
	table       string
	confDelType string
}{
	{"fk_pins_user", "pins", "a"},
	{"fk_reactions_pin", "reactions", "c"},
	{"fk_reactions_user", "reactions", "a"},
	{"fk_pin_discoveries_user", "pin_discoveries", "a"},
	{"fk_pin_discoveries_pin", "pin_discoveries", "a"},
	{"fk_pin_discoveries_triggered_by", "pin_discoveries", "a"},
	{"fk_friendships_requester", "friendships", "a"},
	{"fk_friendships_receiver", "friendships", "a"},
	{"fk_notifications_user", "notifications", "a"},
}

func openMigrationDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = defaultTestDSN
	}
	db, err := gorm.Open(postgres.New(postgres.Config{DSN: dsn}), &gorm.Config{})
	if err != nil {
		t.Skipf("postgres unavailable: %v", err)
	}
	return db
}

// applyAllMigrations は schema_migrations を消して 001..005 を確実に再適用する。
// 他テスト（migrate_002 等）が pins を drop して 005 を skip 状態にしている可能性が
// あるため、本テストは記録をリセットしてから適用し既知の状態を作る。
func applyAllMigrations(t *testing.T, db *gorm.DB) {
	t.Helper()
	if err := db.Exec("drop table if exists schema_migrations").Error; err != nil {
		t.Fatalf("drop schema_migrations: %v", err)
	}
	if err := Migrate(db); err != nil {
		t.Fatalf("AutoMigrate: %v", err)
	}
	if err := MigrateSQL(db); err != nil {
		t.Fatalf("MigrateSQL: %v", err)
	}
}

// TestMigration005_AddsForeignKeys は、全マイグレーション適用後に model.md §2 の FK が
// pg_constraint に存在し、削除時アクションも一致し、存在しない userId での Pin 作成が
// DB レベルで拒否されることを確認する（issue #47 の受け入れ基準）。
func TestMigration005_AddsForeignKeys(t *testing.T) {
	db := openMigrationDB(t)
	applyAllMigrations(t, db)

	for _, fk := range expectedForeignKeys {
		var delType string
		if err := db.Raw(
			`select confdeltype from pg_constraint where conname = ? and contype = 'f'`, fk.name,
		).Row().Scan(&delType); err != nil {
			t.Fatalf("FK %s on %s not found: %v", fk.name, fk.table, err)
		}
		if delType != fk.confDelType {
			t.Errorf("FK %s confdeltype = %q, want %q", fk.name, delType, fk.confDelType)
		}
	}

	// 存在しない userId での Pin 作成は FK で拒否される。
	if err := db.Exec(
		`insert into pins (user_id, body, location)
		 values (gen_random_uuid(), 'orphan', st_setsrid(st_makepoint(139.7, 35.6), 4326)::geography)`,
	).Error; err == nil {
		t.Fatal("inserting pin with non-existent user_id should be rejected by FK")
	}
}

// TestMigration005_CleansOrphansBeforeAddingFK は、孤児行がある状態で 005 を適用すると
// 孤児が掃除されてから FK が張られ、有効データは残ることを確認する。
func TestMigration005_CleansOrphansBeforeAddingFK(t *testing.T) {
	db := openMigrationDB(t)
	applyAllMigrations(t, db)

	// 005 適用前（孤児行が残りうる状態）を再現するため、付与済み FK を一旦落とす。
	for _, fk := range expectedForeignKeys {
		if err := db.Exec("alter table " + fk.table + " drop constraint if exists " + fk.name).Error; err != nil {
			t.Fatalf("drop constraint %s: %v", fk.name, err)
		}
	}
	if err := db.Exec("truncate users, pins, friendships, reactions, pin_discoveries, notifications cascade").Error; err != nil {
		t.Fatalf("truncate: %v", err)
	}

	// 有効データ: user u1 と、その pin p1、p1 への reaction。
	var u1 string
	if err := db.Raw(
		`insert into users (user_id, display_name, auth_provider, auth_uid)
		 values ('valid', 'Valid', 'google', 'valid-uid') returning id`,
	).Row().Scan(&u1); err != nil {
		t.Fatalf("seed user: %v", err)
	}
	var p1 string
	if err := db.Raw(
		`insert into pins (user_id, body, location)
		 values (?, 'valid pin', st_setsrid(st_makepoint(139.7, 35.6), 4326)::geography) returning id`, u1,
	).Row().Scan(&p1); err != nil {
		t.Fatalf("seed pin: %v", err)
	}
	if err := db.Exec(`insert into reactions (pin_id, user_id) values (?, ?)`, p1, u1).Error; err != nil {
		t.Fatalf("seed reaction: %v", err)
	}

	// 孤児データ（FK が無い今だけ挿入できる）。ghost は存在しない user/pin の id。
	const ghost = "00000000-0000-0000-0000-0000000000ff"
	if err := db.Exec(
		`insert into pins (user_id, body, location)
		 values (?, 'orphan pin', st_setsrid(st_makepoint(1, 1), 4326)::geography)`, ghost,
	).Error; err != nil {
		t.Fatalf("seed orphan pin: %v", err)
	}
	if err := db.Exec(`insert into reactions (pin_id, user_id) values (?, ?)`, ghost, u1).Error; err != nil {
		t.Fatalf("seed orphan reaction: %v", err)
	}
	if err := db.Exec(`insert into notifications (user_id, kind, payload) values (?, 'reaction', '{}'::jsonb)`, ghost).Error; err != nil {
		t.Fatalf("seed orphan notification: %v", err)
	}
	if err := db.Exec(`insert into friendships (requester_id, receiver_id, status) values (?, ?, 'pending')`, u1, ghost).Error; err != nil {
		t.Fatalf("seed orphan friendship: %v", err)
	}

	// 005 を直接適用（孤児を掃除して FK を張る）。
	body, err := os.ReadFile("migrations/005_foreign_keys.sql")
	if err != nil {
		t.Fatalf("read migration: %v", err)
	}
	if err := db.Exec(string(body)).Error; err != nil {
		t.Fatalf("apply 005: %v", err)
	}

	assertCount := func(label, q string, want int64) {
		var n int64
		if err := db.Raw(q).Scan(&n).Error; err != nil {
			t.Fatalf("%s: %v", label, err)
		}
		if n != want {
			t.Errorf("%s = %d, want %d", label, n, want)
		}
	}
	// 孤児は消え、有効データは残る。
	assertCount("pins", "select count(*) from pins", 1)
	assertCount("reactions", "select count(*) from reactions", 1)
	assertCount("notifications", "select count(*) from notifications", 0)
	assertCount("friendships", "select count(*) from friendships", 0)

	// FK が張られている。
	for _, fk := range expectedForeignKeys {
		var cnt int64
		if err := db.Raw(`select count(*) from pg_constraint where conname = ? and contype = 'f'`, fk.name).Scan(&cnt).Error; err != nil {
			t.Fatalf("check %s: %v", fk.name, err)
		}
		if cnt != 1 {
			t.Errorf("FK %s missing after 005", fk.name)
		}
	}

	// 冪等: 二度目の適用もエラーにならない。
	if err := db.Exec(string(body)).Error; err != nil {
		t.Fatalf("re-apply 005: %v", err)
	}
}
