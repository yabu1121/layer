package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/cymed/layer/backend/internal/model"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

func setupNotifDB(t *testing.T) *gorm.DB {
	db := setupAuthDB(t) // User AutoMigrate + truncate users + Skip if no DB
	if err := db.AutoMigrate(&model.Notification{}); err != nil {
		t.Fatalf("automigrate: %v", err)
	}
	if err := db.Exec("truncate notifications").Error; err != nil {
		t.Fatalf("truncate: %v", err)
	}
	return db
}

func seedNotif(t *testing.T, db *gorm.DB, userID, kind, payload string) {
	t.Helper()
	if err := db.Exec(
		`insert into notifications (user_id, kind, payload, created_at) values (?, ?, ?::jsonb, now())`,
		userID, kind, payload,
	).Error; err != nil {
		t.Fatalf("seed notif: %v", err)
	}
}

func notifEcho(db *gorm.DB) *echo.Echo {
	e := echo.New()
	n := NewNotificationHandler(db)
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, authStubVerify))
	api.GET("/notifications", n.List)
	api.POST("/notifications/read-all", n.ReadAll)
	api.GET("/notifications/unread-count", n.UnreadCount)
	return e
}

func notifReq(e *echo.Echo, method, path, token string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, nil)
	if token != "" {
		req.Header.Set(echo.HeaderAuthorization, "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	return rec
}

func TestNotifications_ListOwnOnlyAndLimit(t *testing.T) {
	db := setupNotifDB(t)
	me := insertUser(t, db, "me_user", "google-sub-1")
	other := insertUser(t, db, "other", "other-sub")
	seedNotif(t, db, me, "discovery", `{"k":"v1"}`)
	seedNotif(t, db, me, "reaction", `{"k":"v2"}`)
	seedNotif(t, db, me, "friend_request", `{"k":"v3"}`)
	seedNotif(t, db, other, "discovery", `{"k":"other"}`)
	e := notifEcho(db)

	// 自分宛のみ（3 件）。
	rec := notifReq(e, http.MethodGet, "/api/notifications", "good")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	var got struct {
		Notifications []struct {
			Kind    string          `json:"kind"`
			Payload json.RawMessage `json:"payload"`
		} `json:"notifications"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(got.Notifications) != 3 {
		t.Fatalf("notifications = %d, want 3 (own only)", len(got.Notifications))
	}
	// payload が JSON オブジェクトとして正しい。
	var p map[string]string
	if err := json.Unmarshal(got.Notifications[0].Payload, &p); err != nil {
		t.Fatalf("payload not valid JSON object: %v", err)
	}
	if p["k"] == "" {
		t.Fatalf("payload missing key k: %s", got.Notifications[0].Payload)
	}

	// limit が効く。
	rec = notifReq(e, http.MethodGet, "/api/notifications?limit=2", "good")
	var limited struct {
		Notifications []json.RawMessage `json:"notifications"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &limited)
	if len(limited.Notifications) != 2 {
		t.Fatalf("limited = %d, want 2", len(limited.Notifications))
	}
}

func TestNotifications_ReadAllThenUnreadZero(t *testing.T) {
	db := setupNotifDB(t)
	me := insertUser(t, db, "me_user", "google-sub-1")
	seedNotif(t, db, me, "discovery", `{"k":"v1"}`)
	seedNotif(t, db, me, "reaction", `{"k":"v2"}`)
	e := notifEcho(db)

	// 既読化前は 2 件未読。
	rec := notifReq(e, http.MethodGet, "/api/notifications/unread-count", "good")
	var before struct {
		Count int64 `json:"count"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &before)
	if before.Count != 2 {
		t.Fatalf("unread before = %d, want 2", before.Count)
	}

	rec = notifReq(e, http.MethodPost, "/api/notifications/read-all", "good")
	if rec.Code != http.StatusOK {
		t.Fatalf("read-all status = %d", rec.Code)
	}
	var updated struct {
		Updated int64 `json:"updated"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &updated)
	if updated.Updated != 2 {
		t.Fatalf("updated = %d, want 2", updated.Updated)
	}

	rec = notifReq(e, http.MethodGet, "/api/notifications/unread-count", "good")
	var after struct {
		Count int64 `json:"count"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &after)
	if after.Count != 0 {
		t.Fatalf("unread after = %d, want 0", after.Count)
	}
}

func TestNotifications_Unauthenticated401(t *testing.T) {
	db := setupNotifDB(t)
	e := notifEcho(db)

	for _, tc := range []struct{ method, path string }{
		{http.MethodGet, "/api/notifications"},
		{http.MethodPost, "/api/notifications/read-all"},
		{http.MethodGet, "/api/notifications/unread-count"},
	} {
		if rec := notifReq(e, tc.method, tc.path, ""); rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s %s = %d, want 401", tc.method, tc.path, rec.Code)
		}
	}
}
