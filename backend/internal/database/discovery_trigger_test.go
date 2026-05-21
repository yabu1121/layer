package database

import (
	"os"
	"testing"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// 東京駅付近を基準に、緯度 0.0001° ≒ 11m を使って近接/遠方を作る。
const (
	baseLat = 35.681236
	baseLng = 139.767125
	near    = 0.0001 // ≒ 11m（20m 以内）
	far     = 0.0003 // ≒ 33m（20m 超）
)

func openDiscoveryDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = defaultTestDSN
	}
	db, err := gorm.Open(postgres.New(postgres.Config{DSN: dsn}), &gorm.Config{})
	if err != nil {
		t.Skipf("postgres unavailable: %v", err)
	}
	if err := Migrate(db); err != nil {
		t.Fatalf("AutoMigrate: %v", err)
	}
	if err := MigrateSQL(db); err != nil {
		t.Fatalf("MigrateSQL: %v", err)
	}
	return db
}

func resetDiscoveryData(t *testing.T, db *gorm.DB) {
	t.Helper()
	// FK 追加後（issue #47）は reactions も pins・users を参照するため cascade で消す。
	if err := db.Exec("truncate users, pins, friendships, pin_discoveries, notifications cascade").Error; err != nil {
		t.Fatalf("truncate: %v", err)
	}
}

func seedUser(t *testing.T, db *gorm.DB, handle, name string) string {
	t.Helper()
	var id string
	if err := db.Raw(
		`insert into users (user_id, display_name, auth_provider, auth_uid)
		 values (?, ?, 'google', ?) returning id`,
		handle, name, handle+"-uid",
	).Row().Scan(&id); err != nil {
		t.Fatalf("seed user %s: %v", handle, err)
	}
	return id
}

func seedAcceptedFriendship(t *testing.T, db *gorm.DB, a, b string) {
	t.Helper()
	if err := db.Exec(
		`insert into friendships (requester_id, receiver_id, status, created_at)
		 values (?, ?, 'accepted', now())`, a, b,
	).Error; err != nil {
		t.Fatalf("seed friendship: %v", err)
	}
}

// insertPin は Pin を INSERT する（AFTER INSERT トリガーが発火する）。
func insertPin(t *testing.T, db *gorm.DB, userID, body string, lat, lng float64) string {
	t.Helper()
	var id string
	if err := db.Raw(
		`insert into pins (user_id, body, location, created_at)
		 values (?, ?, st_setsrid(st_makepoint(?, ?), 4326)::geography, now())
		 returning id`, userID, body, lng, lat,
	).Row().Scan(&id); err != nil {
		t.Fatalf("insert pin: %v", err)
	}
	return id
}

func count(t *testing.T, db *gorm.DB, q string, args ...any) int64 {
	t.Helper()
	var n int64
	if err := db.Raw(q, args...).Scan(&n).Error; err != nil {
		t.Fatalf("count query: %v", err)
	}
	return n
}

func TestDiscoveryTrigger(t *testing.T) {
	db := openDiscoveryDB(t)

	t.Run("friend nearby creates discovery and two notifications", func(t *testing.T) {
		resetDiscoveryData(t, db)
		a := seedUser(t, db, "alice", "Alice")
		b := seedUser(t, db, "bob", "Bob")
		seedAcceptedFriendship(t, db, a, b)

		bPin := insertPin(t, db, b, "ボブの場所", baseLat, baseLng)
		aPin := insertPin(t, db, a, "アリスの場所", baseLat+near, baseLng)

		if got := count(t, db,
			`select count(*) from pin_discoveries where user_id=? and pin_id=? and triggered_by=?`,
			a, bPin, aPin); got != 1 {
			t.Fatalf("pin_discoveries = %d, want 1", got)
		}
		// 双方向に discovery 通知。
		if got := count(t, db, `select count(*) from notifications where user_id=? and kind='discovery'`, b); got != 1 {
			t.Fatalf("notifications to owner = %d, want 1", got)
		}
		if got := count(t, db, `select count(*) from notifications where user_id=? and kind='discovery'`, a); got != 1 {
			t.Fatalf("notifications to new poster = %d, want 1", got)
		}
		// 通知 payload に相手の情報が入っている（持ち主 b への通知 = 相手は alice）。
		var displayName string
		if err := db.Raw(
			`select payload->>'displayName' from notifications where user_id=? and kind='discovery'`, b,
		).Row().Scan(&displayName); err != nil {
			t.Fatalf("payload: %v", err)
		}
		if displayName != "Alice" {
			t.Fatalf("payload displayName = %q, want Alice", displayName)
		}
	})

	t.Run("non-friend nearby creates nothing", func(t *testing.T) {
		resetDiscoveryData(t, db)
		a := seedUser(t, db, "alice", "Alice")
		c := seedUser(t, db, "carol", "Carol") // 友達関係なし

		insertPin(t, db, c, "キャロルの場所", baseLat, baseLng)
		insertPin(t, db, a, "アリスの場所", baseLat+near, baseLng)

		if got := count(t, db, `select count(*) from pin_discoveries`); got != 0 {
			t.Fatalf("pin_discoveries = %d, want 0", got)
		}
		if got := count(t, db, `select count(*) from notifications`); got != 0 {
			t.Fatalf("notifications = %d, want 0", got)
		}
	})

	t.Run("more than 21m away does not fire", func(t *testing.T) {
		resetDiscoveryData(t, db)
		a := seedUser(t, db, "alice", "Alice")
		b := seedUser(t, db, "bob", "Bob")
		seedAcceptedFriendship(t, db, a, b)

		insertPin(t, db, b, "ボブの場所", baseLat, baseLng)
		insertPin(t, db, a, "遠いアリス", baseLat+far, baseLng)

		if got := count(t, db, `select count(*) from pin_discoveries`); got != 0 {
			t.Fatalf("pin_discoveries = %d, want 0", got)
		}
		if got := count(t, db, `select count(*) from notifications`); got != 0 {
			t.Fatalf("notifications = %d, want 0", got)
		}
	})

	t.Run("same owner multiple pins aggregates to one notification per owner", func(t *testing.T) {
		resetDiscoveryData(t, db)
		a := seedUser(t, db, "alice", "Alice")
		b := seedUser(t, db, "bob", "Bob")
		seedAcceptedFriendship(t, db, a, b)

		insertPin(t, db, b, "ボブ1", baseLat, baseLng)
		insertPin(t, db, b, "ボブ2", baseLat+near*0.2, baseLng) // 同じ持ち主の近接 Pin 2 件
		aPin := insertPin(t, db, a, "アリス", baseLat+near, baseLng)

		// 発見ログは既存 Pin の件数ぶん（2 件）。
		if got := count(t, db,
			`select count(*) from pin_discoveries where user_id=? and triggered_by=?`, a, aPin); got != 2 {
			t.Fatalf("pin_discoveries = %d, want 2", got)
		}
		// 通知は持ち主ごとに集約（持ち主 b へ 1、新規投稿者 a へ 1）。
		if got := count(t, db, `select count(*) from notifications where user_id=?`, b); got != 1 {
			t.Fatalf("notifications to owner = %d, want 1 (aggregated)", got)
		}
		if got := count(t, db, `select count(*) from notifications where user_id=?`, a); got != 1 {
			t.Fatalf("notifications to new poster = %d, want 1 (aggregated)", got)
		}
	})
}
