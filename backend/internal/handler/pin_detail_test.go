package handler

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"gorm.io/gorm"
)

func seedPinReturningID(t *testing.T, db *gorm.DB, userID, body string, lat, lng float64) string {
	t.Helper()
	var id string
	if err := db.Raw(
		`insert into pins (user_id, body, location, created_at)
		 values (?, ?, st_setsrid(st_makepoint(?, ?), 4326)::geography, now()) returning id`,
		userID, body, lng, lat,
	).Row().Scan(&id); err != nil {
		t.Fatalf("seed pin: %v", err)
	}
	return id
}

func resetPinDomain(t *testing.T, db *gorm.DB) {
	t.Helper()
	// FK 追加後（issue #47）は reactions / pin_discoveries も pins・users を参照するため cascade で消す。
	if err := db.Exec("truncate pins, users, friendships, notifications cascade").Error; err != nil {
		t.Fatalf("truncate: %v", err)
	}
}

func TestPinGet_AccessControl(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db)
	me := seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	friend := seedNamedUser(t, db, "friend_user", "friend-sub", "Friend", "😀")
	stranger := seedNamedUser(t, db, "stranger", "stranger-sub", "Stranger", "🥶")
	seedFriendship(t, db, me, friend, "accepted")

	myPin := seedPinReturningID(t, db, me, "mine", 35.0, 139.0)
	friendPin := seedPinReturningID(t, db, friend, "friend's", 35.0, 139.0)
	strangerPin := seedPinReturningID(t, db, stranger, "stranger's", 35.0, 139.0)
	e := authedPinEcho(db)

	t.Run("own pin 200", func(t *testing.T) {
		if rec := getAt(e, "/api/pins/"+myPin, "good"); rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
		}
	})
	t.Run("friend pin 200 with author", func(t *testing.T) {
		rec := getAt(e, "/api/pins/"+friendPin, "good")
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200", rec.Code)
		}
		var got struct {
			Pin struct {
				Author struct {
					DisplayName string `json:"displayName"`
				} `json:"author"`
			} `json:"pin"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &got)
		if got.Pin.Author.DisplayName != "Friend" {
			t.Fatalf("author = %q, want Friend", got.Pin.Author.DisplayName)
		}
	})
	t.Run("non-friend pin 403", func(t *testing.T) {
		if rec := getAt(e, "/api/pins/"+strangerPin, "good"); rec.Code != http.StatusForbidden {
			t.Fatalf("status = %d, want 403", rec.Code)
		}
	})
	t.Run("missing pin 404", func(t *testing.T) {
		if rec := getAt(e, "/api/pins/00000000-0000-0000-0000-000000000000", "good"); rec.Code != http.StatusNotFound {
			t.Fatalf("status = %d, want 404", rec.Code)
		}
	})
	t.Run("unauthenticated 401", func(t *testing.T) {
		if rec := getAt(e, "/api/pins/"+myPin, ""); rec.Code != http.StatusUnauthorized {
			t.Fatalf("status = %d, want 401", rec.Code)
		}
	})
}

func TestPinNearby(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db)
	me := seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	friend := seedNamedUser(t, db, "friend_user", "friend-sub", "Friend", "😀")
	stranger := seedNamedUser(t, db, "stranger", "stranger-sub", "Stranger", "🥶")
	seedFriendship(t, db, me, friend, "accepted")

	const (
		baseLat = 35.681236
		baseLng = 139.767125
		near    = 0.0001 // ≒ 11m
		far     = 0.0003 // ≒ 33m
	)
	base := seedPinReturningID(t, db, me, "base", baseLat, baseLng)
	seedPinReturningID(t, db, me, "my-near", baseLat+near, baseLng)         // 自分・近い → 含む
	seedPinReturningID(t, db, friend, "friend-near", baseLat+near, baseLng) // 友達・近い → 含む
	seedPinReturningID(t, db, stranger, "stranger-near", baseLat+near, baseLng) // 非友達 → 除外
	seedPinReturningID(t, db, friend, "friend-far", baseLat+far, baseLng)   // 友達だが遠い → 除外
	e := authedPinEcho(db)

	t.Run("returns nearby own+friends, excludes base/stranger/far", func(t *testing.T) {
		rec := getAt(e, "/api/pins/"+base+"/nearby", "good")
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
		}
		var got struct {
			Pins []struct {
				Body string `json:"body"`
			} `json:"pins"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
			t.Fatalf("decode: %v", err)
		}
		bodies := map[string]bool{}
		for _, p := range got.Pins {
			bodies[p.Body] = true
		}
		if len(got.Pins) != 2 || !bodies["my-near"] || !bodies["friend-near"] {
			t.Fatalf("nearby = %v, want my-near+friend-near", bodies)
		}
		if bodies["base"] || bodies["stranger-near"] || bodies["friend-far"] {
			t.Fatalf("nearby leaked base/stranger/far: %v", bodies)
		}
	})

	t.Run("missing base 404", func(t *testing.T) {
		if rec := getAt(e, "/api/pins/00000000-0000-0000-0000-000000000000/nearby", "good"); rec.Code != http.StatusNotFound {
			t.Fatalf("status = %d, want 404", rec.Code)
		}
	})
}

func TestPinNearby_EmptyIsArray(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db)
	me := seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	base := seedPinReturningID(t, db, me, "base", 35.0, 139.0)
	e := authedPinEcho(db)

	rec := getAt(e, "/api/pins/"+base+"/nearby", "good")
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"pins":[]`) {
		t.Fatalf("empty: code=%d body=%s, want 200 + []", rec.Code, rec.Body.String())
	}
}
