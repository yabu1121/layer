package handler

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"gorm.io/gorm"
)

func seedNamedUser(t *testing.T, db *gorm.DB, userID, authUID, displayName, icon string) string {
	t.Helper()
	var id string
	if err := db.Raw(
		`insert into users (user_id, display_name, icon, auth_provider, auth_uid)
		 values (?, ?, ?, 'google', ?) returning id`, userID, displayName, icon, authUID,
	).Row().Scan(&id); err != nil {
		t.Fatalf("seed user %s: %v", userID, err)
	}
	return id
}

func seedVisiblePin(t *testing.T, db *gorm.DB, userID, body string, lat, lng float64) {
	t.Helper()
	if err := db.Exec(
		`insert into pins (user_id, body, location, created_at)
		 values (?, ?, st_setsrid(st_makepoint(?, ?), 4326)::geography, now())`,
		userID, body, lng, lat,
	).Error; err != nil {
		t.Fatalf("seed pin: %v", err)
	}
}

type visibleBody struct {
	Pins []struct {
		UserID string `json:"userId"`
		Author struct {
			UserID      string `json:"userId"`
			DisplayName string `json:"displayName"`
		} `json:"author"`
	} `json:"pins"`
}

func TestListVisible_OwnAndFriendsOnly(t *testing.T) {
	db := setupDB(t)
	// FK 追加後（issue #47）は reactions / pin_discoveries も pins・users を参照するため cascade で消す。
	if err := db.Exec("truncate pins, users, friendships, notifications cascade").Error; err != nil {
		t.Fatalf("truncate: %v", err)
	}
	me := seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	friend := seedNamedUser(t, db, "friend_user", "friend-sub", "Friend", "😀")
	stranger := seedNamedUser(t, db, "stranger", "stranger-sub", "Stranger", "🥶")
	// accepted な友達関係（向きは me→friend）。
	seedFriendship(t, db, me, friend, "accepted")

	seedVisiblePin(t, db, me, "mine", 35.0, 139.0)
	seedVisiblePin(t, db, friend, "friend's", 35.1, 139.1)
	seedVisiblePin(t, db, stranger, "stranger's", 35.2, 139.2)

	e := authedPinEcho(db)
	rec := serveAuth(e, http.MethodGet, "/api/pins/visible", "good", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	var got visibleBody
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	handles := map[string]string{} // pin author handle -> displayName
	for _, p := range got.Pins {
		handles[p.Author.UserID] = p.Author.DisplayName
	}
	if len(got.Pins) != 2 {
		t.Fatalf("visible pins = %d, want 2 (%s)", len(got.Pins), rec.Body.String())
	}
	if _, ok := handles["me_user"]; !ok {
		t.Fatal("own pin should always be included")
	}
	if _, ok := handles["friend_user"]; !ok {
		t.Fatal("friend pin should be included")
	}
	if _, ok := handles["stranger"]; ok {
		t.Fatal("non-friend pin must not be included")
	}
	if handles["friend_user"] != "Friend" {
		t.Fatalf("author displayName = %q, want Friend", handles["friend_user"])
	}
}

func TestListVisible_EmptyIsArray(t *testing.T) {
	db := setupDB(t)
	// FK 追加後（issue #47）は reactions / pin_discoveries も pins・users を参照するため cascade で消す。
	if err := db.Exec("truncate pins, users, friendships, notifications cascade").Error; err != nil {
		t.Fatalf("truncate: %v", err)
	}
	seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	e := authedPinEcho(db)

	rec := serveAuth(e, http.MethodGet, "/api/pins/visible", "good", "")
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"pins":[]`) {
		t.Fatalf("empty: code=%d body=%s, want 200 + []", rec.Code, rec.Body.String())
	}
}

func TestListVisible_Unauthenticated401(t *testing.T) {
	db := setupDB(t)
	e := authedPinEcho(db)

	if rec := serveAuth(e, http.MethodGet, "/api/pins/visible", "", ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}
