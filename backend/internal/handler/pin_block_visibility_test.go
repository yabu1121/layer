package handler

import (
	"net/http"
	"testing"

	"gorm.io/gorm"
)

func seedBlock(t *testing.T, db *gorm.DB, blocker, blocked string) {
	t.Helper()
	if err := db.Exec(`insert into blocks (blocker_id, blocked_id) values (?, ?)`,
		blocker, blocked).Error; err != nil {
		t.Fatalf("seed block: %v", err)
	}
}

func TestBlockVisibility_PublicExcludesBlocked(t *testing.T) {
	t.Setenv("PINS_PUBLIC", "1")
	db := setupDB(t)
	resetPinDomain(t, db)
	me := seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	other := seedNamedUser(t, db, "other_user", "other-sub", "Other", "😀")
	myPin := seedPinReturningID(t, db, me, "mine", 35.0, 139.0)
	otherPin := seedPinReturningID(t, db, other, "other's", 35.0, 139.0)
	seedBlock(t, db, me, other) // me が other をブロック
	e := authedPinEcho(db)

	// 一覧（公開モード）: ブロック相手は出ない、自分は残る。
	rec := serveAuth(e, http.MethodGet, "/api/pins/visible", "good", "")
	handles := publicVisibleHandles(t, rec.Body.Bytes())
	if handles["other_user"] {
		t.Fatalf("blocked user pin must be excluded from visible: %v", handles)
	}
	if !handles["me_user"] {
		t.Fatalf("own pin should remain: %v", handles)
	}

	// 近傍（公開モード）: ブロック相手は出ない。
	near := getAt(e, "/api/pins/"+myPin+"/nearby", "good")
	if h := publicVisibleHandles(t, near.Body.Bytes()); h["other_user"] {
		t.Fatalf("blocked user pin must be excluded from nearby: %v", h)
	}

	// 詳細: ブロック相手の Pin は 403。
	if rec := getAt(e, "/api/pins/"+otherPin, "good"); rec.Code != http.StatusForbidden {
		t.Fatalf("get blocked pin status = %d, want 403 (%s)", rec.Code, rec.Body.String())
	}

	// 反応: ブロック相手の Pin には付けられない（403）。
	re := reactionEcho(db)
	if rec := reactionReq(re, http.MethodPost, "/api/pins/"+otherPin+"/reactions", "good"); rec.Code != http.StatusForbidden {
		t.Fatalf("react to blocked pin status = %d, want 403 (%s)", rec.Code, rec.Body.String())
	}
}

func TestBlockVisibility_ReverseDirectionAlsoBlocks(t *testing.T) {
	t.Setenv("PINS_PUBLIC", "1")
	db := setupDB(t)
	resetPinDomain(t, db)
	me := seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	other := seedNamedUser(t, db, "other_user", "other-sub", "Other", "😀")
	otherPin := seedPinReturningID(t, db, other, "other's", 35.0, 139.0)
	seedBlock(t, db, other, me) // other が me をブロック（逆向き）
	e := authedPinEcho(db)

	// 逆向きのブロックでも詳細は 403。
	if rec := getAt(e, "/api/pins/"+otherPin, "good"); rec.Code != http.StatusForbidden {
		t.Fatalf("get status = %d, want 403 (reverse block)", rec.Code)
	}
}
