package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/cymed/layer/backend/internal/model"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

func assertErrorBody(t *testing.T, rec *httptest.ResponseRecorder, want string) {
	t.Helper()
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode error body: %v", err)
	}
	if body["error"] != want {
		t.Fatalf("error = %q, want %q", body["error"], want)
	}
}

// setupFriendDB は users / friendships / notifications を用意してまっさらにする。
func setupFriendDB(t *testing.T) *gorm.DB {
	db := setupAuthDB(t) // User の AutoMigrate + truncate users + DB 不在なら Skip
	if err := db.AutoMigrate(&model.Friendship{}, &model.Notification{}); err != nil {
		t.Fatalf("automigrate: %v", err)
	}
	if err := db.Exec("truncate friendships, notifications").Error; err != nil {
		t.Fatalf("truncate: %v", err)
	}
	return db
}

func insertUser(t *testing.T, db *gorm.DB, userID, authUID string) string {
	t.Helper()
	var id string
	if err := db.Raw(
		`insert into users (user_id, display_name, auth_provider, auth_uid)
		 values (?, '', 'google', ?) returning id`, userID, authUID,
	).Row().Scan(&id); err != nil {
		t.Fatalf("insert user %s: %v", userID, err)
	}
	return id
}

func friendEcho(db *gorm.DB) *echo.Echo {
	e := echo.New()
	f := NewFriendHandler(db)
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, authStubVerify))
	api.POST("/friends/requests", f.SendRequest)
	api.POST("/friends/requests/:id/accept", f.Accept)
	api.POST("/friends/requests/:id/reject", f.Reject)
	return e
}

func seedFriendship(t *testing.T, db *gorm.DB, requester, receiver, status string) string {
	t.Helper()
	var id string
	if err := db.Raw(
		`insert into friendships (requester_id, receiver_id, status, created_at)
		 values (?, ?, ?, now()) returning id`, requester, receiver, status,
	).Row().Scan(&id); err != nil {
		t.Fatalf("seed friendship: %v", err)
	}
	return id
}

func postAt(e *echo.Echo, path, token string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, path, nil)
	if token != "" {
		req.Header.Set(echo.HeaderAuthorization, "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	return rec
}

func sendRequest(e *echo.Echo, receiverID, token string) *httptest.ResponseRecorder {
	body := `{"receiver_id":"` + receiverID + `"}`
	req := httptest.NewRequest(http.MethodPost, "/api/friends/requests", strings.NewReader(body))
	req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	if token != "" {
		req.Header.Set(echo.HeaderAuthorization, "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	return rec
}

func friendshipStatus(t *testing.T, db *gorm.DB, requester, receiver string) string {
	t.Helper()
	var status string
	db.Raw(`select status from friendships where requester_id = ? and receiver_id = ?`, requester, receiver).Row().Scan(&status)
	return status
}

func TestSendRequest_CreatesPendingAndNotifies(t *testing.T) {
	db := setupFriendDB(t)
	me := insertUser(t, db, "me_user", "google-sub-1")
	bob := insertUser(t, db, "bob", "bob-sub")
	e := friendEcho(db)

	rec := sendRequest(e, bob, "good")
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (%s)", rec.Code, rec.Body.String())
	}
	if got := friendshipStatus(t, db, me, bob); got != "pending" {
		t.Fatalf("friendship status = %q, want pending", got)
	}
	var notif int64
	db.Raw(`select count(*) from notifications where user_id = ? and kind = 'friend_request'`, bob).Scan(&notif)
	if notif != 1 {
		t.Fatalf("friend_request notifications = %d, want 1", notif)
	}
}

func TestSendRequest_ToSelfIs400(t *testing.T) {
	db := setupFriendDB(t)
	me := insertUser(t, db, "me_user", "google-sub-1")
	e := friendEcho(db)

	if rec := sendRequest(e, me, "good"); rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}

func TestSendRequest_AlreadyFriendsIs409(t *testing.T) {
	db := setupFriendDB(t)
	me := insertUser(t, db, "me_user", "google-sub-1")
	bob := insertUser(t, db, "bob", "bob-sub")
	// 既に accepted（向きは逆でも友達）。
	if err := db.Exec(
		`insert into friendships (requester_id, receiver_id, status, created_at) values (?, ?, 'accepted', now())`,
		bob, me,
	).Error; err != nil {
		t.Fatalf("seed friendship: %v", err)
	}
	e := friendEcho(db)

	rec := sendRequest(e, bob, "good")
	if rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409", rec.Code)
	}
	assertErrorBody(t, rec, "already_friends")
}

func TestSendRequest_AlreadyPendingIs409(t *testing.T) {
	db := setupFriendDB(t)
	me := insertUser(t, db, "me_user", "google-sub-1")
	bob := insertUser(t, db, "bob", "bob-sub")
	if err := db.Exec(
		`insert into friendships (requester_id, receiver_id, status, created_at) values (?, ?, 'pending', now())`,
		me, bob,
	).Error; err != nil {
		t.Fatalf("seed friendship: %v", err)
	}
	e := friendEcho(db)

	rec := sendRequest(e, bob, "good")
	if rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409", rec.Code)
	}
	assertErrorBody(t, rec, "already_requested")
}

func TestSendRequest_RejectedIsRevived(t *testing.T) {
	db := setupFriendDB(t)
	me := insertUser(t, db, "me_user", "google-sub-1")
	bob := insertUser(t, db, "bob", "bob-sub")
	if err := db.Exec(
		`insert into friendships (requester_id, receiver_id, status, created_at) values (?, ?, 'rejected', now())`,
		me, bob,
	).Error; err != nil {
		t.Fatalf("seed friendship: %v", err)
	}
	e := friendEcho(db)

	rec := sendRequest(e, bob, "good")
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (%s)", rec.Code, rec.Body.String())
	}
	if got := friendshipStatus(t, db, me, bob); got != "pending" {
		t.Fatalf("status = %q, want pending (revived)", got)
	}
	// 行は増えていない（復活であって新規作成ではない）。
	var count int64
	db.Raw(`select count(*) from friendships where requester_id = ? and receiver_id = ?`, me, bob).Scan(&count)
	if count != 1 {
		t.Fatalf("friendship rows = %d, want 1", count)
	}
}

func TestSendRequest_ReceiverNotFoundIs404(t *testing.T) {
	db := setupFriendDB(t)
	insertUser(t, db, "me_user", "google-sub-1")
	e := friendEcho(db)

	if rec := sendRequest(e, "00000000-0000-0000-0000-000000000000", "good"); rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", rec.Code)
	}
}

func TestSendRequest_Unauthenticated401(t *testing.T) {
	db := setupFriendDB(t)
	bob := insertUser(t, db, "bob", "bob-sub")
	e := friendEcho(db)

	if rec := sendRequest(e, bob, ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func TestAccept_SetsAcceptedAndNotifiesRequester(t *testing.T) {
	db := setupFriendDB(t)
	me := insertUser(t, db, "me_user", "google-sub-1")   // receiver
	bob := insertUser(t, db, "bob", "bob-sub")           // requester
	id := seedFriendship(t, db, bob, me, "pending")
	e := friendEcho(db)

	rec := postAt(e, "/api/friends/requests/"+id+"/accept", "good")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}

	var status string
	var acceptedAt *time.Time
	if err := db.Raw(`select status, accepted_at from friendships where id = ?`, id).Row().Scan(&status, &acceptedAt); err != nil {
		t.Fatalf("query friendship: %v", err)
	}
	if status != "accepted" {
		t.Fatalf("status = %q, want accepted", status)
	}
	if acceptedAt == nil {
		t.Fatal("accepted_at should be set")
	}
	var notif int64
	db.Raw(`select count(*) from notifications where user_id = ? and kind = 'friend_accepted'`, bob).Scan(&notif)
	if notif != 1 {
		t.Fatalf("friend_accepted notifications = %d, want 1", notif)
	}
}

func TestAccept_OthersRequestIs403(t *testing.T) {
	db := setupFriendDB(t)
	insertUser(t, db, "me_user", "google-sub-1")
	bob := insertUser(t, db, "bob", "bob-sub")
	carol := insertUser(t, db, "carol", "carol-sub")
	// receiver は carol（自分=me_user ではない）。
	id := seedFriendship(t, db, bob, carol, "pending")
	e := friendEcho(db)

	if rec := postAt(e, "/api/friends/requests/"+id+"/accept", "good"); rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", rec.Code)
	}
}

func TestReject_SetsRejectedNoNotification(t *testing.T) {
	db := setupFriendDB(t)
	me := insertUser(t, db, "me_user", "google-sub-1")
	bob := insertUser(t, db, "bob", "bob-sub")
	id := seedFriendship(t, db, bob, me, "pending")
	e := friendEcho(db)

	rec := postAt(e, "/api/friends/requests/"+id+"/reject", "good")
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	if got := friendshipStatus(t, db, bob, me); got != "rejected" {
		t.Fatalf("status = %q, want rejected", got)
	}
	var notif int64
	db.Raw(`select count(*) from notifications`).Scan(&notif)
	if notif != 0 {
		t.Fatalf("notifications = %d, want 0 (reject is silent)", notif)
	}
}

func TestAcceptReject_MissingIDIs404(t *testing.T) {
	db := setupFriendDB(t)
	insertUser(t, db, "me_user", "google-sub-1")
	e := friendEcho(db)

	missing := "00000000-0000-0000-0000-000000000000"
	if rec := postAt(e, "/api/friends/requests/"+missing+"/accept", "good"); rec.Code != http.StatusNotFound {
		t.Fatalf("accept status = %d, want 404", rec.Code)
	}
	if rec := postAt(e, "/api/friends/requests/"+missing+"/reject", "good"); rec.Code != http.StatusNotFound {
		t.Fatalf("reject status = %d, want 404", rec.Code)
	}
}
