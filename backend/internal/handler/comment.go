package handler

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/cymed/layer/backend/internal/model"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

// CommentHandler は Pin へのコメントのエンドポイントを束ねる（US-C3）。
type CommentHandler struct {
	db *gorm.DB
}

// NewCommentHandler は CommentHandler を生成する。
func NewCommentHandler(db *gorm.DB) *CommentHandler {
	return &CommentHandler{db: db}
}

// maxCommentLen はコメント本文の最大文字数（FR と整合、Pin 本文と同じ 200）。
const maxCommentLen = 200

type commentItem struct {
	ID        string     `json:"id"`
	Body      string     `json:"body"`
	CreatedAt time.Time  `json:"createdAt"`
	User      publicUser `json:"user"`
}

type commentsResponse struct {
	Comments []commentItem `json:"comments"`
}

type createCommentRequest struct {
	Body string `json:"body"`
}

type commentResponse struct {
	Comment commentItem `json:"comment"`
}

// List は対象 Pin のコメント一覧を投稿者つきで返す（古い順）。
func (h *CommentHandler) List(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	if _, authErr := authorizePinView(h.db, c, me); authErr != nil {
		return authErr
	}

	type row struct {
		ID          string    `gorm:"column:id"`
		Body        string    `gorm:"column:body"`
		CreatedAt   time.Time `gorm:"column:created_at"`
		UserID      string    `gorm:"column:user_id"`
		Handle      string    `gorm:"column:handle"`
		DisplayName string    `gorm:"column:display_name"`
		Icon        string    `gorm:"column:icon"`
	}
	var rows []row
	const q = `
select c.id as id, c.body as body, c.created_at as created_at,
       u.id as user_id, u.user_id as handle,
       u.display_name as display_name, u.icon as icon
from comments c
join users u on u.id = c.user_id
where c.pin_id = ?
order by c.created_at asc`
	if err := h.db.Raw(q, c.Param("id")).Scan(&rows).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	comments := make([]commentItem, 0, len(rows))
	for _, r := range rows {
		comments = append(comments, commentItem{
			ID:        r.ID,
			Body:      r.Body,
			CreatedAt: r.CreatedAt,
			User:      publicUser{ID: r.UserID, UserID: r.Handle, DisplayName: r.DisplayName, Icon: r.Icon},
		})
	}
	return c.JSON(http.StatusOK, commentsResponse{Comments: comments})
}

// Create は対象 Pin にコメントを付ける（US-C3）。本文は 1〜200 文字。
// owner（自分以外）には comment 通知を作る。
func (h *CommentHandler) Create(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	ownerID, authErr := authorizePinView(h.db, c, me)
	if authErr != nil {
		return authErr
	}

	var req createCommentRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, "invalid body")
	}
	body := strings.TrimSpace(req.Body)
	if body == "" {
		return echo.NewHTTPError(http.StatusBadRequest, "body is required")
	}
	if utf8.RuneCountInString(body) > maxCommentLen {
		return echo.NewHTTPError(http.StatusBadRequest, "body too long")
	}

	comment := model.Comment{PinID: c.Param("id"), UserID: me.ID, Body: body}
	txErr := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&comment).Error; err != nil {
			return err
		}
		if ownerID == me.ID {
			return nil // 自分の Pin への自コメントは通知を作らない
		}
		payload, _ := json.Marshal(map[string]any{
			"userId":      me.ID,
			"handle":      me.UserID,
			"displayName": me.DisplayName,
			"icon":        me.Icon,
			"pinId":       c.Param("id"),
			"commentId":   comment.ID,
			"body":        body,
		})
		return tx.Create(&model.Notification{
			UserID:  ownerID,
			Kind:    "comment",
			Payload: string(payload),
		}).Error
	})
	if txErr != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, txErr.Error())
	}
	return c.JSON(http.StatusCreated, commentResponse{Comment: commentItem{
		ID:        comment.ID,
		Body:      comment.Body,
		CreatedAt: comment.CreatedAt,
		User:      toPublicUser(*me),
	}})
}

// DeleteMine は自分のコメントを削除する（冪等。無くても 204）。
// 他人のコメントは消せない（user_id 条件で守る）。
func (h *CommentHandler) DeleteMine(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	if err := h.db.Exec(
		`delete from comments where id = ? and pin_id = ? and user_id = ?`,
		c.Param("commentId"), c.Param("id"), me.ID,
	).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.NoContent(http.StatusNoContent)
}
