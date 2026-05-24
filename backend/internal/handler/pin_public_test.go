package handler

import (
	"encoding/json"
	"net/http"
	"testing"
)

// PINS_PUBLIC=1 のとき、非友達の Pin も閲覧・反応できることを確認する。
// 既定（友達限定）の挙動は pin_visible_test.go / pin_detail_test.go が担保する。
// pinsPublic() はリクエスト時に os.Getenv を読むため t.Setenv で切り替えられる。

func publicVisibleHandles(t *testing.T, body []byte) map[string]bool {
	t.Helper()
	var got visibleBody
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	handles := map[string]bool{}
	for _, p := range got.Pins {
		handles[p.Author.UserID] = true
	}
	return handles
}

func TestPinsPublic_ListVisibleIncludesStrangers(t *testing.T) {
	t.Setenv("PINS_PUBLIC", "1")
	db := setupDB(t)
	setupReactionWorld(t, db) // me / friend / stranger と各自の Pin（同座標）
	e := authedPinEcho(db)

	rec := serveAuth(e, http.MethodGet, "/api/pins/visible", "good", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	handles := publicVisibleHandles(t, rec.Body.Bytes())
	if !handles["stranger"] {
		t.Fatalf("公開モードでは非友達の Pin も見えるべき: %v", handles)
	}
	if !handles["me_user"] || !handles["friend_user"] {
		t.Fatalf("自分・友達の Pin も含むべき: %v", handles)
	}
}

func TestPinsPublic_ScopeFriendsStillRestricts(t *testing.T) {
	t.Setenv("PINS_PUBLIC", "1")
	db := setupDB(t)
	setupReactionWorld(t, db)
	e := authedPinEcho(db)

	rec := serveAuth(e, http.MethodGet, "/api/pins/visible?scope=friends", "good", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	handles := publicVisibleHandles(t, rec.Body.Bytes())
	if handles["stranger"] {
		t.Fatalf("scope=friends は公開モードでも友達限定であるべき: %v", handles)
	}
	if !handles["me_user"] || !handles["friend_user"] {
		t.Fatalf("自分・友達は含むべき: %v", handles)
	}
}

func TestPinsPublic_GetStrangerPin200(t *testing.T) {
	t.Setenv("PINS_PUBLIC", "1")
	db := setupDB(t)
	_, _, _, _, _, strangerPin := setupReactionWorld(t, db)
	e := authedPinEcho(db)

	if rec := getAt(e, "/api/pins/"+strangerPin, "good"); rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (公開モードで非友達 Pin 詳細) (%s)", rec.Code, rec.Body.String())
	}
}

func TestPinsPublic_NearbyIncludesStrangers(t *testing.T) {
	t.Setenv("PINS_PUBLIC", "1")
	db := setupDB(t)
	_, _, _, myPin, _, _ := setupReactionWorld(t, db)
	e := authedPinEcho(db)

	rec := getAt(e, "/api/pins/"+myPin+"/nearby", "good")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	handles := publicVisibleHandles(t, rec.Body.Bytes())
	if !handles["stranger"] {
		t.Fatalf("公開モードの近傍に非友達 Pin が含まれるべき: %v", handles)
	}
}

func TestPinsPublic_ReactToStrangerPin(t *testing.T) {
	t.Setenv("PINS_PUBLIC", "1")
	db := setupDB(t)
	_, _, _, _, _, strangerPin := setupReactionWorld(t, db)
	e := reactionEcho(db)

	rec := reactionReq(e, http.MethodPost, "/api/pins/"+strangerPin+"/reactions", "good")
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (公開モードで非友達 Pin に反応) (%s)", rec.Code, rec.Body.String())
	}
}
