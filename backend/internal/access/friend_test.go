package access

import (
	"os"
	"testing"

	"github.com/cymed/layer/backend/internal/model"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// 他パッケージのテスト DB と衝突しないよう専用 DB を使う。
const (
	defaultAccessDSN = "postgres://postgres:postgres@localhost:5432/layer_test_access?sslmode=disable"
	defaultAdminDSN  = "postgres://postgres:postgres@localhost:5432/postgres?sslmode=disable"
	accessDBName     = "layer_test_access"
)

func TestMain(m *testing.M) {
	ensureDatabase(accessDBName)
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

func setupDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsn := os.Getenv("TEST_ACCESS_DATABASE_URL")
	if dsn == "" {
		dsn = defaultAccessDSN
	}
	db, err := gorm.Open(postgres.New(postgres.Config{DSN: dsn}), &gorm.Config{})
	if err != nil {
		t.Skipf("postgres unavailable: %v", err)
	}
	if err := db.AutoMigrate(&model.Friendship{}); err != nil {
		t.Fatalf("automigrate: %v", err)
	}
	if err := db.Exec("truncate friendships").Error; err != nil {
		t.Fatalf("truncate: %v", err)
	}
	return db
}

func insertFriendship(t *testing.T, db *gorm.DB, requester, receiver, status string) {
	t.Helper()
	if err := db.Exec(
		`insert into friendships (requester_id, receiver_id, status, created_at) values (?, ?, ?, now())`,
		requester, receiver, status,
	).Error; err != nil {
		t.Fatalf("insert friendship: %v", err)
	}
}

func TestIsFriend(t *testing.T) {
	const (
		alice = "11111111-1111-1111-1111-111111111111"
		bob   = "22222222-2222-2222-2222-222222222222"
		carol = "33333333-3333-3333-3333-333333333333"
	)

	assertFriend := func(t *testing.T, db *gorm.DB, viewer, owner string, want bool) {
		t.Helper()
		got, err := IsFriend(db, viewer, owner)
		if err != nil {
			t.Fatalf("IsFriend(%s,%s): %v", viewer, owner, err)
		}
		if got != want {
			t.Fatalf("IsFriend(%s,%s) = %v, want %v", viewer, owner, got, want)
		}
	}

	t.Run("accepted is friend in both directions", func(t *testing.T) {
		db := setupDB(t)
		insertFriendship(t, db, alice, bob, "accepted")
		assertFriend(t, db, alice, bob, true)
		assertFriend(t, db, bob, alice, true)
	})

	t.Run("pending is not friend", func(t *testing.T) {
		db := setupDB(t)
		insertFriendship(t, db, alice, bob, "pending")
		assertFriend(t, db, alice, bob, false)
		assertFriend(t, db, bob, alice, false)
	})

	t.Run("rejected is not friend", func(t *testing.T) {
		db := setupDB(t)
		insertFriendship(t, db, alice, bob, "rejected")
		assertFriend(t, db, alice, bob, false)
	})

	t.Run("no relationship is not friend", func(t *testing.T) {
		db := setupDB(t)
		insertFriendship(t, db, alice, bob, "accepted")
		assertFriend(t, db, alice, carol, false)
	})

	t.Run("viewer equals owner is not friend", func(t *testing.T) {
		db := setupDB(t)
		insertFriendship(t, db, alice, bob, "accepted")
		assertFriend(t, db, alice, alice, false)
	})
}
