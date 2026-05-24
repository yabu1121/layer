package handler

import (
	"net/http"
	"testing"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

func meDeleteEcho(db *gorm.DB) *echo.Echo {
	e := echo.New()
	me := NewMeHandler(db)
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, authStubVerify))
	api.DELETE("/me", me.Delete)
	return e
}

func seedReaction(t *testing.T, db *gorm.DB, pinID, userID string) {
	t.Helper()
	if err := db.Exec(`insert into reactions (pin_id, user_id, kind) values (?, ?, 'wakaru')`,
		pinID, userID).Error; err != nil {
		t.Fatalf("seed reaction: %v", err)
	}
}

func seedComment(t *testing.T, db *gorm.DB, pinID, userID string) {
	t.Helper()
	if err := db.Exec(`insert into comments (pin_id, user_id, body) values (?, ?, 'x')`,
		pinID, userID).Error; err != nil {
		t.Fatalf("seed comment: %v", err)
	}
}

func seedDiscovery(t *testing.T, db *gorm.DB, userID, pinID, triggeredBy string) {
	t.Helper()
	if err := db.Exec(`insert into pin_discoveries (user_id, pin_id, triggered_by) values (?, ?, ?)`,
		userID, pinID, triggeredBy).Error; err != nil {
		t.Fatalf("seed discovery: %v", err)
	}
}

func seedNotif(t *testing.T, db *gorm.DB, userID string) {
	t.Helper()
	if err := db.Exec(`insert into notifications (user_id, kind, payload) values (?, 'reaction', '{}')`,
		userID).Error; err != nil {
		t.Fatalf("seed notif: %v", err)
	}
}

func TestMeDelete_RemovesSelfAndRelatedOnly(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db)
	me := seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	friend := seedNamedUser(t, db, "friend_user", "friend-sub", "Friend", "😀")
	stranger := seedNamedUser(t, db, "stranger", "stranger-sub", "Stranger", "🥶")
	seedFriendship(t, db, me, friend, "accepted")

	myPin := seedPinReturningID(t, db, me, "mine", 35.0, 139.0)
	friendPin := seedPinReturningID(t, db, friend, "friend's", 35.0, 139.0)
	strangerPin := seedPinReturningID(t, db, stranger, "stranger's", 35.0, 139.0)

	// reactions: 自分→友達Pin / 友達→自分Pin / 友達→他人Pin（残るべき）
	seedReaction(t, db, friendPin, me)
	seedReaction(t, db, myPin, friend)
	seedReaction(t, db, strangerPin, friend)
	// comments: 同上
	seedComment(t, db, friendPin, me)
	seedComment(t, db, myPin, friend)
	seedComment(t, db, strangerPin, friend)
	// notifications: 自分宛 / 友達宛（残るべき）
	seedNotif(t, db, me)
	seedNotif(t, db, friend)
	// pin_discoveries: 自分絡み 2 件 / 他人のみ 1 件（残るべき）
	seedDiscovery(t, db, me, friendPin, friendPin)
	seedDiscovery(t, db, friend, myPin, myPin)
	seedDiscovery(t, db, stranger, strangerPin, strangerPin)

	e := meDeleteEcho(db)
	if rec := deleteAt(e, "/api/me", "good"); rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204 (%s)", rec.Code, rec.Body.String())
	}

	// 自分は消え、他ユーザーは残る。
	if n := countRows(t, db, `select count(*) from users where id = ?`, me); n != 0 {
		t.Fatalf("me user remains: %d", n)
	}
	if n := countRows(t, db, `select count(*) from users`); n != 2 {
		t.Fatalf("users = %d, want 2 (friend+stranger)", n)
	}
	// 自分の Pin は消え、他は残る。
	if n := countRows(t, db, `select count(*) from pins where user_id = ?`, me); n != 0 {
		t.Fatalf("my pins remain: %d", n)
	}
	if n := countRows(t, db, `select count(*) from pins`); n != 2 {
		t.Fatalf("pins = %d, want 2", n)
	}
	// reactions: 友達→他人Pin の 1 件だけ残る。
	if n := countRows(t, db, `select count(*) from reactions`); n != 1 {
		t.Fatalf("reactions = %d, want 1 (friend on stranger)", n)
	}
	// comments: 同上 1 件。
	if n := countRows(t, db, `select count(*) from comments`); n != 1 {
		t.Fatalf("comments = %d, want 1", n)
	}
	// pin_discoveries: 他人のみの 1 件だけ残る。
	if n := countRows(t, db, `select count(*) from pin_discoveries`); n != 1 {
		t.Fatalf("pin_discoveries = %d, want 1", n)
	}
	// friendships: 自分絡みは全消滅。
	if n := countRows(t, db, `select count(*) from friendships`); n != 0 {
		t.Fatalf("friendships = %d, want 0", n)
	}
	// notifications: 友達宛の 1 件だけ残る。
	if n := countRows(t, db, `select count(*) from notifications`); n != 1 {
		t.Fatalf("notifications = %d, want 1", n)
	}
}

func TestMeDelete_Unauthenticated401(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db)
	seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	e := meDeleteEcho(db)
	if rec := deleteAt(e, "/api/me", ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}
