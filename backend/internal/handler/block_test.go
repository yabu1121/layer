package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/cymed/layer/backend/internal/access"
	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

func blockEcho(db *gorm.DB) *echo.Echo {
	e := echo.New()
	h := NewBlockHandler(db)
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, authStubVerify))
	api.POST("/blocks/:userId", h.Block)
	api.DELETE("/blocks/:userId", h.Unblock)
	api.GET("/blocks", h.List)
	return e
}

func blockReq(e *echo.Echo, method, path, token string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, nil)
	if token != "" {
		req.Header.Set(echo.HeaderAuthorization, "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	return rec
}

func countBlocks(t *testing.T, db *gorm.DB) int64 {
	t.Helper()
	var n int64
	db.Raw(`select count(*) from blocks`).Scan(&n)
	return n
}

func TestBlock_CreatesAndDissolvesFriendship(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db)
	me := seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	other := seedNamedUser(t, db, "other_user", "other-sub", "Other", "😀")
	seedFriendship(t, db, me, other, "accepted")
	e := blockEcho(db)

	if rec := blockReq(e, http.MethodPost, "/api/blocks/"+other, "good"); rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204 (%s)", rec.Code, rec.Body.String())
	}
	// ブロック行ができる。
	if n := countBlocks(t, db); n != 1 {
		t.Fatalf("blocks = %d, want 1", n)
	}
	// 友達関係が解消される。
	if ok, _ := access.IsFriend(db, me, other); ok {
		t.Fatal("friendship should be dissolved by block")
	}
	// IsBlocked が双方向で true。
	if ok, _ := access.IsBlocked(db, other, me); !ok {
		t.Fatal("IsBlocked should be true (reverse direction)")
	}
}

func TestBlock_Idempotent(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db)
	seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	other := seedNamedUser(t, db, "other_user", "other-sub", "Other", "😀")
	e := blockEcho(db)

	for i := 0; i < 2; i++ {
		if rec := blockReq(e, http.MethodPost, "/api/blocks/"+other, "good"); rec.Code != http.StatusNoContent {
			t.Fatalf("block %d status = %d, want 204", i, rec.Code)
		}
	}
	if n := countBlocks(t, db); n != 1 {
		t.Fatalf("blocks = %d, want 1 (idempotent)", n)
	}
}

func TestBlock_CannotBlockSelf(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db)
	me := seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	e := blockEcho(db)
	if rec := blockReq(e, http.MethodPost, "/api/blocks/"+me, "good"); rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}

func TestBlock_UnblockAndList(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db)
	seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	other := seedNamedUser(t, db, "other_user", "other-sub", "Other", "😀")
	e := blockEcho(db)

	blockReq(e, http.MethodPost, "/api/blocks/"+other, "good")

	// 一覧に出る。
	rec := blockReq(e, http.MethodGet, "/api/blocks", "good")
	if rec.Code != http.StatusOK {
		t.Fatalf("list status = %d, want 200", rec.Code)
	}
	var resp blockedUsersResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp.Blocked) != 1 || resp.Blocked[0].ID != other {
		t.Fatalf("blocked list = %+v, want [%s]", resp.Blocked, other)
	}

	// 解除すると消える（冪等）。
	if rec := blockReq(e, http.MethodDelete, "/api/blocks/"+other, "good"); rec.Code != http.StatusNoContent {
		t.Fatalf("unblock status = %d, want 204", rec.Code)
	}
	if n := countBlocks(t, db); n != 0 {
		t.Fatalf("blocks after unblock = %d, want 0", n)
	}
}

func TestBlock_Unauthenticated401(t *testing.T) {
	db := setupDB(t)
	resetPinDomain(t, db)
	other := seedNamedUser(t, db, "other_user", "other-sub", "Other", "😀")
	e := blockEcho(db)
	if rec := blockReq(e, http.MethodPost, "/api/blocks/"+other, ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}
