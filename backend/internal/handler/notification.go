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

// NotificationHandler は in-app 通知のエンドポイントを束ねる。
type NotificationHandler struct {
	db *gorm.DB
}

// NewNotificationHandler は NotificationHandler を生成する。
func NewNotificationHandler(db *gorm.DB) *NotificationHandler {
	return &NotificationHandler{db: db}
}

const (
	defaultNotifLimit = 50
	maxNotifLimit     = 100
)

type notificationItem struct {
	ID        string          `json:"id"`
	Kind      string          `json:"kind"`
	Payload   json.RawMessage `json:"payload"`
	ReadAt    *time.Time      `json:"readAt,omitempty"`
	CreatedAt time.Time       `json:"createdAt"`
}

type notificationsResponse struct {
	Notifications []notificationItem `json:"notifications"`
}

// List は自分宛の通知を新しい順に返す（FR-6.1）。?limit=N（既定 50・最大 100）。
func (h *NotificationHandler) List(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}

	limit := defaultNotifLimit
	if s := c.QueryParam("limit"); s != "" {
		if n, err := strconv.Atoi(s); err == nil && n > 0 {
			limit = n
		}
	}
	if limit > maxNotifLimit {
		limit = maxNotifLimit
	}

	type row struct {
		ID        string     `gorm:"column:id"`
		Kind      string     `gorm:"column:kind"`
		Payload   string     `gorm:"column:payload"`
		ReadAt    *time.Time `gorm:"column:read_at"`
		CreatedAt time.Time  `gorm:"column:created_at"`
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

// ReadAll は自分宛の未読通知をすべて既読にする（FR-6.1）。
func (h *NotificationHandler) ReadAll(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	res := h.db.Exec(`update notifications set read_at = now() where user_id = ? and read_at is null`, me.ID)
	if res.Error != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, res.Error.Error())
	}
	return c.JSON(http.StatusOK, echo.Map{"updated": res.RowsAffected})
}

// UnreadCount は自分宛の未読通知数を返す（バッジ表示用）。
func (h *NotificationHandler) UnreadCount(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	var count int64
	if err := h.db.Raw(`select count(*) from notifications where user_id = ? and read_at is null`, me.ID).Scan(&count).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, echo.Map{"count": count})
}
