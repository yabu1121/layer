package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

func commentEcho(db *gorm.DB) *echo.Echo {
	e := echo.New()
	h := NewCommentHandler(db)
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, authStubVerify))
	api.GET("/pins/:id/comments", h.List)
	api.POST("/pins/:id/comments", h.Create)
	api.DELETE("/pins/:id/comments/:commentId", h.DeleteMine)
	return e
}

func commentReq(e *echo.Echo, method, path, token, body string) *httptest.ResponseRecorder {
	var req *http.Request
	if body != "" {
		req = httptest.NewRequest(method, path, strings.NewReader(body))
		req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	} else {
		req = httptest.NewRequest(method, path, nil)
	}
	if token != "" {
		req.Header.Set(echo.HeaderAuthorization, "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	return rec
}

func countCommentNotifs(t *testing.T, db *gorm.DB, userID string) int64 {
	t.Helper()
	var n int64
	db.Raw(`select count(*) from notifications where user_id = ? and kind = 'comment'`, userID).Scan(&n)
	return n
}

// 認証ユーザー me(token "good") は friendPin の owner と友達、stranger とは非友達。
func TestComment_CreateOnFriendPinNotifies(t *testing.T) {
	db := setupDB(t)
	_, friend, _, _, friendPin, _ := setupReactionWorld(t, db)
	e := commentEcho(db)

	rec := commentReq(e, http.MethodPost, "/api/pins/"+friendPin+"/comments", "good", `{"body":"いいね！"}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (%s)", rec.Code, rec.Body.String())
	}
	var resp commentResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Comment.Body != "いいね！" || resp.Comment.ID == "" {
		t.Fatalf("unexpected comment: %+v", resp.Comment)
	}
	if got := countCommentNotifs(t, db, friend); got != 1 {
		t.Fatalf("owner notif = %d, want 1", got)
	}
}

func TestComment_CreateOnOwnPinNoNotify(t *testing.T) {
	db := setupDB(t)
	me, _, _, myPin, _, _ := setupReactionWorld(t, db)
	e := commentEcho(db)

	rec := commentReq(e, http.MethodPost, "/api/pins/"+myPin+"/comments", "good", `{"body":"自分用メモ"}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (%s)", rec.Code, rec.Body.String())
	}
	if got := countCommentNotifs(t, db, me); got != 0 {
		t.Fatalf("self notif = %d, want 0", got)
	}
}

func TestComment_CreateOnStrangerPinForbidden(t *testing.T) {
	db := setupDB(t)
	_, _, _, _, _, strangerPin := setupReactionWorld(t, db)
	e := commentEcho(db)

	rec := commentReq(e, http.MethodPost, "/api/pins/"+strangerPin+"/comments", "good", `{"body":"x"}`)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 (%s)", rec.Code, rec.Body.String())
	}
}

func TestComment_CreateValidation(t *testing.T) {
	db := setupDB(t)
	_, _, _, myPin, _, _ := setupReactionWorld(t, db)
	e := commentEcho(db)

	t.Run("empty body 400", func(t *testing.T) {
		rec := commentReq(e, http.MethodPost, "/api/pins/"+myPin+"/comments", "good", `{"body":"  "}`)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("status = %d, want 400", rec.Code)
		}
	})
	t.Run("too long 400", func(t *testing.T) {
		long := `{"body":"` + strings.Repeat("あ", 201) + `"}`
		rec := commentReq(e, http.MethodPost, "/api/pins/"+myPin+"/comments", "good", long)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("status = %d, want 400", rec.Code)
		}
	})
}

func TestComment_CreateNonexistentPin404(t *testing.T) {
	db := setupDB(t)
	setupReactionWorld(t, db)
	e := commentEcho(db)

	rec := commentReq(e, http.MethodPost,
		"/api/pins/00000000-0000-0000-0000-000000000000/comments", "good", `{"body":"x"}`)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 (%s)", rec.Code, rec.Body.String())
	}
}

func TestComment_ListReturnsAuthorsInOrder(t *testing.T) {
	db := setupDB(t)
	_, _, _, _, friendPin, _ := setupReactionWorld(t, db)
	e := commentEcho(db)

	for _, b := range []string{"1番目", "2番目"} {
		if rec := commentReq(e, http.MethodPost, "/api/pins/"+friendPin+"/comments", "good", `{"body":"`+b+`"}`); rec.Code != http.StatusCreated {
			t.Fatalf("seed comment %q: %d (%s)", b, rec.Code, rec.Body.String())
		}
	}

	rec := commentReq(e, http.MethodGet, "/api/pins/"+friendPin+"/comments", "good", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	var resp commentsResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp.Comments) != 2 {
		t.Fatalf("comments = %d, want 2", len(resp.Comments))
	}
	if resp.Comments[0].Body != "1番目" || resp.Comments[1].Body != "2番目" {
		t.Fatalf("order wrong: %+v", resp.Comments)
	}
	if resp.Comments[0].User.DisplayName == "" {
		t.Fatalf("author missing: %+v", resp.Comments[0].User)
	}
}

func TestComment_ListOnStrangerPinForbidden(t *testing.T) {
	db := setupDB(t)
	_, _, _, _, _, strangerPin := setupReactionWorld(t, db)
	e := commentEcho(db)

	rec := commentReq(e, http.MethodGet, "/api/pins/"+strangerPin+"/comments", "good", "")
	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 (%s)", rec.Code, rec.Body.String())
	}
}

func TestComment_DeleteOwnIdempotent(t *testing.T) {
	db := setupDB(t)
	_, _, _, myPin, _, _ := setupReactionWorld(t, db)
	e := commentEcho(db)

	rec := commentReq(e, http.MethodPost, "/api/pins/"+myPin+"/comments", "good", `{"body":"消す"}`)
	var created commentResponse
	_ = json.Unmarshal(rec.Body.Bytes(), &created)

	del := commentReq(e, http.MethodDelete, "/api/pins/"+myPin+"/comments/"+created.Comment.ID, "good", "")
	if del.Code != http.StatusNoContent {
		t.Fatalf("delete status = %d, want 204 (%s)", del.Code, del.Body.String())
	}
	// 冪等: もう一度消しても 204。
	again := commentReq(e, http.MethodDelete, "/api/pins/"+myPin+"/comments/"+created.Comment.ID, "good", "")
	if again.Code != http.StatusNoContent {
		t.Fatalf("re-delete status = %d, want 204", again.Code)
	}
	// 実際に消えている。
	list := commentReq(e, http.MethodGet, "/api/pins/"+myPin+"/comments", "good", "")
	var resp commentsResponse
	_ = json.Unmarshal(list.Body.Bytes(), &resp)
	if len(resp.Comments) != 0 {
		t.Fatalf("comments after delete = %d, want 0", len(resp.Comments))
	}
}

func TestComment_Unauthenticated401(t *testing.T) {
	db := setupDB(t)
	_, _, _, myPin, _, _ := setupReactionWorld(t, db)
	e := commentEcho(db)

	rec := commentReq(e, http.MethodGet, "/api/pins/"+myPin+"/comments", "", "")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}
