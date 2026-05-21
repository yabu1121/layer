package handler

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

// NotificationHandler は in-app 通知のエンドポイントを束ねる（FR-6.1〜6.3 / US-D2, US-D3）。
type NotificationHandler struct {
	db *gorm.DB
}

// NewNotificationHandler は NotificationHandler を生成する。
func NewNotificationHandler(db *gorm.DB) *NotificationHandler {
	return &NotificationHandler{db: db}
}

const (
	defaultNotificationLimit = 50
	maxNotificationLimit     = 100
)

// notificationItem は通知1件の API 表現。payload は jsonb をそのまま入れ子の
// JSON として返すため json.RawMessage で扱う（文字列としてエスケープしない）。
type notificationItem struct {
	ID        string          `json:"id"`
	Kind      string          `json:"kind"`
	Payload   json.RawMessage `json:"payload"`
	ReadAt    *time.Time      `json:"readAt"`
	CreatedAt time.Time       `json:"createdAt"`
}

type notificationsResponse struct {
	Notifications []notificationItem `json:"notifications"`
}

// List は自分宛の通知を created_at DESC で返す（FR-6.1）。
// ?limit でページサイズを指定（既定 50、最大 100）。
func (h *NotificationHandler) List(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}

	limit := defaultNotificationLimit
	if raw := c.QueryParam("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 {
			return echo.NewHTTPError(http.StatusBadRequest, "limit must be a positive integer")
		}
		if n > maxNotificationLimit {
			n = maxNotificationLimit
		}
		limit = n
	}

	type row struct {
		ID        string
		Kind      string
		Payload   string
		ReadAt    *time.Time
		CreatedAt time.Time
	}
	var rows []row
	const q = `select id, kind, payload, read_at, created_at
		from notifications
		where user_id = ?
		order by created_at desc
		limit ?`
	if err := h.db.Raw(q, me.ID, limit).Scan(&rows).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	items := make([]notificationItem, 0, len(rows))
	for _, r := range rows {
		items = append(items, notificationItem{
			ID:        r.ID,
			Kind:      r.Kind,
			Payload:   json.RawMessage(r.Payload),
			ReadAt:    r.ReadAt,
			CreatedAt: r.CreatedAt,
		})
	}
	return c.JSON(http.StatusOK, notificationsResponse{Notifications: items})
}

type readAllResponse struct {
	Updated int64 `json:"updated"`
}

// ReadAll は自分宛の未読通知をすべて既読化し、更新件数を返す。
func (h *NotificationHandler) ReadAll(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	res := h.db.Exec(
		`update notifications set read_at = now() where user_id = ? and read_at is null`, me.ID,
	)
	if res.Error != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, res.Error.Error())
	}
	return c.JSON(http.StatusOK, readAllResponse{Updated: res.RowsAffected})
}

type unreadCountResponse struct {
	Count int64 `json:"count"`
}

// UnreadCount は自分宛の未読通知数を返す（MapScreen のバッジ用 / FR-6.1）。
func (h *NotificationHandler) UnreadCount(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	var count int64
	if err := h.db.Raw(
		`select count(*) from notifications where user_id = ? and read_at is null`, me.ID,
	).Scan(&count).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, unreadCountResponse{Count: count})
}
