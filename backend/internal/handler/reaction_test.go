package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

func reactionEcho(db *gorm.DB) *echo.Echo {
	e := echo.New()
	r := NewReactionHandler(db)
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, authStubVerify))
	api.GET("/pins/:id/reactions", r.List)
	api.POST("/pins/:id/reactions", r.Create)
	api.DELETE("/pins/:id/reactions/me", r.DeleteMine)
	return e
}

func reactionReq(e *echo.Echo, method, path, token string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, nil)
	if token != "" {
		req.Header.Set(echo.HeaderAuthorization, "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	return rec
}

// 自分(me)・友達(friend)・非友達(stranger) と各自の Pin を用意する。
func setupReactionWorld(t *testing.T, db *gorm.DB) (me, friend, stranger, myPin, friendPin, strangerPin string) {
	t.Helper()
	resetPinDomain(t, db)
	me = seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	friend = seedNamedUser(t, db, "friend_user", "friend-sub", "Friend", "😀")
	stranger = seedNamedUser(t, db, "stranger", "stranger-sub", "Stranger", "🥶")
	seedFriendship(t, db, me, friend, "accepted")
	myPin = seedPinReturningID(t, db, me, "mine", 35.0, 139.0)
	friendPin = seedPinReturningID(t, db, friend, "friend's", 35.0, 139.0)
	strangerPin = seedPinReturningID(t, db, stranger, "stranger's", 35.0, 139.0)
	return
}

func countReactionNotifs(t *testing.T, db *gorm.DB, userID string) int64 {
	t.Helper()
	var n int64
	db.Raw(`select count(*) from notifications where user_id = ? and kind = 'reaction'`, userID).Scan(&n)
	return n
}

func TestReaction_FriendPinSucceedsAndNotifies(t *testing.T) {
	db := setupDB(t)
	_, friend, _, _, friendPin, _ := setupReactionWorld(t, db)
	e := reactionEcho(db)

	rec := reactionReq(e, http.MethodPost, "/api/pins/"+friendPin+"/reactions", "good")
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (%s)", rec.Code, rec.Body.String())
	}
	if got := countReactionNotifs(t, db, friend); got != 1 {
		t.Fatalf("owner reaction notifs = %d, want 1", got)
	}
}

func TestReaction_DoublePressIs409(t *testing.T) {
	db := setupDB(t)
	_, _, _, _, friendPin, _ := setupReactionWorld(t, db)
	e := reactionEcho(db)

	if rec := reactionReq(e, http.MethodPost, "/api/pins/"+friendPin+"/reactions", "good"); rec.Code != http.StatusCreated {
		t.Fatalf("first react status = %d, want 201", rec.Code)
	}
	rec := reactionReq(e, http.MethodPost, "/api/pins/"+friendPin+"/reactions", "good")
	if rec.Code != http.StatusConflict {
		t.Fatalf("second react status = %d, want 409", rec.Code)
	}
	assertErrorBody(t, rec, "already_reacted")
}

func TestReaction_OwnPinNoSelfNotification(t *testing.T) {
	db := setupDB(t)
	me, _, _, myPin, _, _ := setupReactionWorld(t, db)
	e := reactionEcho(db)

	if rec := reactionReq(e, http.MethodPost, "/api/pins/"+myPin+"/reactions", "good"); rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (%s)", rec.Code, rec.Body.String())
	}
	if got := countReactionNotifs(t, db, me); got != 0 {
		t.Fatalf("self notifs = %d, want 0", got)
	}
}

func TestReaction_NonFriendPinIs403(t *testing.T) {
	db := setupDB(t)
	_, _, _, _, _, strangerPin := setupReactionWorld(t, db)
	e := reactionEcho(db)

	for _, tc := range []struct {
		method, path string
	}{
		{http.MethodPost, "/api/pins/" + strangerPin + "/reactions"},
		{http.MethodGet, "/api/pins/" + strangerPin + "/reactions"},
		{http.MethodDelete, "/api/pins/" + strangerPin + "/reactions/me"},
	} {
		if rec := reactionReq(e, tc.method, tc.path, "good"); rec.Code != http.StatusForbidden {
			t.Fatalf("%s %s = %d, want 403", tc.method, tc.path, rec.Code)
		}
	}
}

func TestReaction_DeleteAndList(t *testing.T) {
	db := setupDB(t)
	_, _, _, _, friendPin, _ := setupReactionWorld(t, db)
	e := reactionEcho(db)

	if rec := reactionReq(e, http.MethodPost, "/api/pins/"+friendPin+"/reactions", "good"); rec.Code != http.StatusCreated {
		t.Fatalf("react status = %d", rec.Code)
	}

	// 一覧に自分（me_user）が出る。
	rec := reactionReq(e, http.MethodGet, "/api/pins/"+friendPin+"/reactions", "good")
	if rec.Code != http.StatusOK {
		t.Fatalf("list status = %d", rec.Code)
	}
	var got struct {
		Reactions []struct {
			User struct {
				UserID string `json:"userId"`
			} `json:"user"`
		} `json:"reactions"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &got)
	if len(got.Reactions) != 1 || got.Reactions[0].User.UserID != "me_user" {
		t.Fatalf("reactions = %+v, want 1 by me_user", got.Reactions)
	}

	// 取り消し → 204 → 一覧 0 件。
	if rec := reactionReq(e, http.MethodDelete, "/api/pins/"+friendPin+"/reactions/me", "good"); rec.Code != http.StatusNoContent {
		t.Fatalf("delete status = %d, want 204", rec.Code)
	}
	var cnt int64
	db.Raw(`select count(*) from reactions where pin_id = ?`, friendPin).Scan(&cnt)
	if cnt != 0 {
		t.Fatalf("reactions after delete = %d, want 0", cnt)
	}
}

func TestReaction_Unauthenticated401(t *testing.T) {
	db := setupDB(t)
	_, _, _, _, friendPin, _ := setupReactionWorld(t, db)
	e := reactionEcho(db)

	if rec := reactionReq(e, http.MethodPost, "/api/pins/"+friendPin+"/reactions", ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}
