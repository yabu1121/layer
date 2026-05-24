package handler

import (
	"net/http"
	"testing"

	"github.com/cymed/layer/backend/internal/access"
	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

func unfriendEcho(db *gorm.DB) *echo.Echo {
	e := echo.New()
	f := NewFriendHandler(db)
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, authStubVerify))
	api.DELETE("/friends/:userId", f.Unfriend)
	return e
}

func TestUnfriend_RemovesAcceptedAsRequester(t *testing.T) {
	db := setupFriendDB(t)
	me := insertUser(t, db, "me_user", "google-sub-1")
	friend := insertUser(t, db, "friend_user", "friend-sub")
	seedFriendship(t, db, me, friend, "accepted") // me=requester
	e := unfriendEcho(db)

	if rec := deleteAt(e, "/api/friends/"+friend, "good"); rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204 (%s)", rec.Code, rec.Body.String())
	}
	if ok, _ := access.IsFriend(db, me, friend); ok {
		t.Fatal("should no longer be friends")
	}
}

func TestUnfriend_RemovesAcceptedAsReceiver(t *testing.T) {
	db := setupFriendDB(t)
	me := insertUser(t, db, "me_user", "google-sub-1")
	friend := insertUser(t, db, "friend_user", "friend-sub")
	seedFriendship(t, db, friend, me, "accepted") // me=receiver（逆向き）
	e := unfriendEcho(db)

	if rec := deleteAt(e, "/api/friends/"+friend, "good"); rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	if ok, _ := access.IsFriend(db, me, friend); ok {
		t.Fatal("should no longer be friends (receiver 側)")
	}
}

func TestUnfriend_Idempotent(t *testing.T) {
	db := setupFriendDB(t)
	insertUser(t, db, "me_user", "google-sub-1")
	other := insertUser(t, db, "other_user", "other-sub")
	e := unfriendEcho(db)

	if rec := deleteAt(e, "/api/friends/"+other, "good"); rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204 (idempotent)", rec.Code)
	}
}

func TestUnfriend_Unauthenticated401(t *testing.T) {
	db := setupFriendDB(t)
	insertUser(t, db, "me_user", "google-sub-1")
	other := insertUser(t, db, "other_user", "other-sub")
	e := unfriendEcho(db)

	if rec := deleteAt(e, "/api/friends/"+other, ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}
