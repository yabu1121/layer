package handler

import (
	"encoding/json"
	"net/http"
	"testing"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

// meLocationEcho は現在地共有（点表示）ルートを登録した echo を返す。
func meLocationEcho(db *gorm.DB) *echo.Echo {
	e := echo.New()
	me := NewMeHandler(db)
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, authStubVerify))
	api.POST("/me/location", me.UpdateLocation)
	api.GET("/locations", me.ListOthersLocations)
	return e
}

func TestMe_UpdateLocationPersists(t *testing.T) {
	db := setupAuthDB(t)
	seedMe(t, db, "me_user")
	e := meLocationEcho(db)

	rec := serveAuth(e, http.MethodPost, "/api/me/location", "good", `{"lat":35.5,"lng":139.5}`)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204 (%s)", rec.Code, rec.Body.String())
	}

	var lat, lng float64
	db.Raw(`select last_lat from users where auth_uid = 'google-sub-1'`).Scan(&lat)
	db.Raw(`select last_lng from users where auth_uid = 'google-sub-1'`).Scan(&lng)
	if lat != 35.5 || lng != 139.5 {
		t.Fatalf("stored (%v,%v), want (35.5,139.5)", lat, lng)
	}
	var withTime int64
	db.Raw(`select count(*) from users
	        where auth_uid = 'google-sub-1' and last_location_at is not null`).Scan(&withTime)
	if withTime != 1 {
		t.Fatal("last_location_at should be set")
	}
}

func TestMe_ListOthersLocationsFriendsOnly(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db) // users / friendships を truncate
	seedMe(t, db, "me_user")
	var meID string
	db.Raw(`select id from users where auth_uid='google-sub-1'`).Scan(&meID)

	// 自分にも位置を入れるが、結果からは除外されるべき。
	if err := db.Exec(
		`update users set last_lat=10, last_lng=20, last_location_at=now() where id=?`, meID,
	).Error; err != nil {
		t.Fatalf("update me loc: %v", err)
	}
	// 友達かつ位置あり → 含まれる。
	friendLoc := seedNamedUser(t, db, "friend_loc", "sub-fl", "FriendLoc", "🙂")
	seedFriendship(t, db, meID, friendLoc, "accepted")
	if err := db.Exec(
		`update users set last_lat=35.1, last_lng=139.1, last_location_at=now() where id=?`, friendLoc,
	).Error; err != nil {
		t.Fatalf("update friend loc: %v", err)
	}
	// 非友達かつ位置あり → 除外される（友達限定）。
	stranger := seedNamedUser(t, db, "stranger_loc", "sub-sl", "StrangerLoc", "🥶")
	if err := db.Exec(
		`update users set last_lat=36, last_lng=140, last_location_at=now() where id=?`, stranger,
	).Error; err != nil {
		t.Fatalf("update stranger loc: %v", err)
	}
	// 友達だが位置なし → 除外される（null）。
	noLoc := seedNamedUser(t, db, "no_loc", "sub-no", "NoLoc", "😶")
	seedFriendship(t, db, meID, noLoc, "accepted")

	e := meLocationEcho(db)
	rec := serveAuth(e, http.MethodGet, "/api/locations", "good", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	var got struct {
		Locations []struct {
			UserID string  `json:"userId"`
			Lat    float64 `json:"lat"`
			Lng    float64 `json:"lng"`
		} `json:"locations"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(got.Locations) != 1 {
		t.Fatalf("locations = %d, want 1 (friend_loc のみ) (%s)", len(got.Locations), rec.Body.String())
	}
	if got.Locations[0].UserID != friendLoc {
		t.Fatalf("userId = %q, want %q (友達のみ)", got.Locations[0].UserID, friendLoc)
	}
	if got.Locations[0].Lat != 35.1 || got.Locations[0].Lng != 139.1 {
		t.Fatalf("loc = (%v,%v), want (35.1,139.1)", got.Locations[0].Lat, got.Locations[0].Lng)
	}
}

func TestMe_LocationUnauthenticated401(t *testing.T) {
	db := setupAuthDB(t)
	seedMe(t, db, "me_user")
	e := meLocationEcho(db)
	if rec := serveAuth(e, http.MethodGet, "/api/locations", "", ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}
