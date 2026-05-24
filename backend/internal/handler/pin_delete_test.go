package handler

import (
	"net/http"
	"net/http/httptest"
	"testing"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

func deleteAt(e *echo.Echo, path, token string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodDelete, path, nil)
	if token != "" {
		req.Header.Set(echo.HeaderAuthorization, "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	return rec
}

func pinDeleteEcho(db *gorm.DB) *echo.Echo {
	e := echo.New()
	p := NewPinHandler(db)
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, authStubVerify))
	api.DELETE("/pins/:id", p.Delete)
	return e
}

func countRows(t *testing.T, db *gorm.DB, q string, args ...any) int64 {
	t.Helper()
	var n int64
	if err := db.Raw(q, args...).Scan(&n).Error; err != nil {
		t.Fatalf("count: %v", err)
	}
	return n
}

func TestPinDelete_OwnerCascades(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db)
	me := seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	friend := seedNamedUser(t, db, "friend_user", "friend-sub", "Friend", "😀")
	seedFriendship(t, db, me, friend, "accepted")
	myPin := seedPinReturningID(t, db, me, "mine", 35.0, 139.0)

	// 関連レコード（削除で消えることを確認）。reactions/comments は FK cascade、
	// pin_discoveries は handler が明示削除する。
	if err := db.Exec(`insert into reactions (pin_id, user_id, kind) values (?, ?, 'wakaru')`,
		myPin, friend).Error; err != nil {
		t.Fatalf("seed reaction: %v", err)
	}
	if err := db.Exec(`insert into comments (pin_id, user_id, body) values (?, ?, 'hi')`,
		myPin, friend).Error; err != nil {
		t.Fatalf("seed comment: %v", err)
	}
	if err := db.Exec(`insert into pin_discoveries (user_id, pin_id, triggered_by) values (?, ?, ?)`,
		me, myPin, myPin).Error; err != nil {
		t.Fatalf("seed discovery: %v", err)
	}

	e := pinDeleteEcho(db)
	if rec := deleteAt(e, "/api/pins/"+myPin, "good"); rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204 (%s)", rec.Code, rec.Body.String())
	}
	if n := countRows(t, db, `select count(*) from pins where id = ?`, myPin); n != 0 {
		t.Fatalf("pin remains: %d", n)
	}
	if n := countRows(t, db, `select count(*) from reactions where pin_id = ?`, myPin); n != 0 {
		t.Fatalf("reactions remain: %d", n)
	}
	if n := countRows(t, db, `select count(*) from comments where pin_id = ?`, myPin); n != 0 {
		t.Fatalf("comments remain: %d", n)
	}
	if n := countRows(t, db,
		`select count(*) from pin_discoveries where pin_id = ? or triggered_by = ?`, myPin, myPin); n != 0 {
		t.Fatalf("pin_discoveries remain: %d", n)
	}
}

func TestPinDelete_NonOwnerForbidden(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db)
	seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	friend := seedNamedUser(t, db, "friend_user", "friend-sub", "Friend", "😀")
	friendPin := seedPinReturningID(t, db, friend, "friend's", 35.0, 139.0)

	e := pinDeleteEcho(db)
	if rec := deleteAt(e, "/api/pins/"+friendPin, "good"); rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 (%s)", rec.Code, rec.Body.String())
	}
	if n := countRows(t, db, `select count(*) from pins where id = ?`, friendPin); n != 1 {
		t.Fatalf("friend pin should remain, count = %d", n)
	}
}

func TestPinDelete_NotFound404(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db)
	seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	e := pinDeleteEcho(db)
	if rec := deleteAt(e, "/api/pins/00000000-0000-0000-0000-000000000000", "good"); rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", rec.Code)
	}
}

func TestPinDelete_Unauthenticated401(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db)
	me := seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	myPin := seedPinReturningID(t, db, me, "mine", 35.0, 139.0)
	e := pinDeleteEcho(db)
	if rec := deleteAt(e, "/api/pins/"+myPin, ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}
