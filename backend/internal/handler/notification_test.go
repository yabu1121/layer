package handler

import (
	"encoding/json"
	"net/http"
	"testing"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

func authedNotificationEcho(db *gorm.DB) *echo.Echo {
	e := echo.New()
	n := NewNotificationHandler(db)
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, authStubVerify))
	api.GET("/notifications", n.List)
	api.POST("/notifications/read-all", n.ReadAll)
	api.GET("/notifications/unread-count", n.UnreadCount)
	return e
}

// setupNotificationWorld はテーブルを掃除し、me（token "good" = auth_uid google-sub-1）と
// other を作って返す。
func setupNotificationWorld(t *testing.T, db *gorm.DB) (me, other string) {
	t.Helper()
	if err := db.Exec("truncate pins, users, friendships, notifications cascade").Error; err != nil {
		t.Fatalf("truncate: %v", err)
	}
	me = seedNamedUser(t, db, "me_user", "google-sub-1", "Me", "🙂")
	other = seedNamedUser(t, db, "other_user", "other-sub", "Other", "😀")
	return me, other
}

// seedNotification は通知を1件作る。minutesAgo で created_at をずらし、read で既読にする。
func seedNotification(t *testing.T, db *gorm.DB, userID, payload string, minutesAgo int, read bool) {
	t.Helper()
	readExpr := "null"
	if read {
		readExpr = "now()"
	}
	q := `insert into notifications (user_id, kind, payload, read_at, created_at)
		values (?, 'reaction', ?::jsonb, ` + readExpr + `, now() - make_interval(mins => ?))`
	if err := db.Exec(q, userID, payload, minutesAgo).Error; err != nil {
		t.Fatalf("seed notification: %v", err)
	}
}

type notificationsBody struct {
	Notifications []struct {
		ID        string          `json:"id"`
		Kind      string          `json:"kind"`
		Payload   json.RawMessage `json:"payload"`
		ReadAt    *string         `json:"readAt"`
		CreatedAt string          `json:"createdAt"`
	} `json:"notifications"`
}

// 受け入れ基準: /notifications は自分宛のみ・created_at DESC・payload は正しい JSON。
func TestNotifications_ListOwnOnlyOrderedPayloadJSON(t *testing.T) {
	db := setupDB(t)
	me, other := setupNotificationWorld(t, db)
	seedNotification(t, db, me, `{"n":"old"}`, 10, false)
	seedNotification(t, db, me, `{"n":"new"}`, 1, false)
	seedNotification(t, db, other, `{"n":"theirs"}`, 5, false) // 他人宛は返らない

	e := authedNotificationEcho(db)
	rec := serveAuth(e, http.MethodGet, "/api/notifications", "good", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	var body notificationsBody
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(body.Notifications) != 2 {
		t.Fatalf("got %d notifications, want 2 (own only)", len(body.Notifications))
	}
	// payload は入れ子の JSON オブジェクトとして妥当。
	var first map[string]string
	if err := json.Unmarshal(body.Notifications[0].Payload, &first); err != nil {
		t.Fatalf("payload is not a valid JSON object: %v (%s)", err, body.Notifications[0].Payload)
	}
	// created_at DESC: 新しい "new" が先頭。
	if first["n"] != "new" {
		t.Fatalf("first payload n = %q, want \"new\" (DESC order)", first["n"])
	}
}

// 受け入れ基準: limit が動く（指定で件数が変わる／不正値は 400）。
func TestNotifications_Limit(t *testing.T) {
	db := setupDB(t)
	me, _ := setupNotificationWorld(t, db)
	for i := range 3 {
		seedNotification(t, db, me, `{}`, i+1, false)
	}
	e := authedNotificationEcho(db)

	count := func(path string) int {
		rec := serveAuth(e, http.MethodGet, path, "good", "")
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s status = %d, want 200 (%s)", path, rec.Code, rec.Body.String())
		}
		var body notificationsBody
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Fatalf("unmarshal: %v", err)
		}
		return len(body.Notifications)
	}

	if got := count("/api/notifications?limit=2"); got != 2 {
		t.Fatalf("limit=2 returned %d, want 2", got)
	}
	if got := count("/api/notifications"); got != 3 {
		t.Fatalf("no limit returned %d, want 3 (all)", got)
	}
	// limit が max を超えても 400 にはせず丸めるだけ（件数は全件）。
	if got := count("/api/notifications?limit=1000"); got != 3 {
		t.Fatalf("limit=1000 returned %d, want 3", got)
	}
	// 不正な limit は 400。
	for _, bad := range []string{"0", "-1", "abc"} {
		if rec := serveAuth(e, http.MethodGet, "/api/notifications?limit="+bad, "good", ""); rec.Code != http.StatusBadRequest {
			t.Fatalf("limit=%s status = %d, want 400", bad, rec.Code)
		}
	}
}

// 受け入れ基準: read-all 後に unread-count=0。
func TestNotifications_ReadAllThenUnreadCountZero(t *testing.T) {
	db := setupDB(t)
	me, _ := setupNotificationWorld(t, db)
	seedNotification(t, db, me, `{}`, 3, false) // 未読
	seedNotification(t, db, me, `{}`, 2, false) // 未読
	seedNotification(t, db, me, `{}`, 1, true)  // 既読
	e := authedNotificationEcho(db)

	unread := func() int64 {
		rec := serveAuth(e, http.MethodGet, "/api/notifications/unread-count", "good", "")
		if rec.Code != http.StatusOK {
			t.Fatalf("unread-count status = %d, want 200 (%s)", rec.Code, rec.Body.String())
		}
		var body struct {
			Count int64 `json:"count"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Fatalf("unmarshal: %v", err)
		}
		return body.Count
	}

	if got := unread(); got != 2 {
		t.Fatalf("initial unread-count = %d, want 2", got)
	}

	rec := serveAuth(e, http.MethodPost, "/api/notifications/read-all", "good", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("read-all status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	var ra struct {
		Updated int64 `json:"updated"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &ra); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if ra.Updated != 2 {
		t.Fatalf("read-all updated = %d, want 2", ra.Updated)
	}

	if got := unread(); got != 0 {
		t.Fatalf("unread-count after read-all = %d, want 0", got)
	}
}

func TestNotifications_Unauthenticated401(t *testing.T) {
	db := setupDB(t)
	setupNotificationWorld(t, db)
	e := authedNotificationEcho(db)

	for _, tc := range []struct{ method, path string }{
		{http.MethodGet, "/api/notifications"},
		{http.MethodPost, "/api/notifications/read-all"},
		{http.MethodGet, "/api/notifications/unread-count"},
	} {
		if rec := serveAuth(e, tc.method, tc.path, "", ""); rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s %s status = %d, want 401", tc.method, tc.path, rec.Code)
		}
	}
}
