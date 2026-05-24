package handler

import (
	"net/http"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

// BlockHandler はユーザーのブロック関連エンドポイントを束ねる（US-A7）。
type BlockHandler struct {
	db *gorm.DB
}

// NewBlockHandler は BlockHandler を生成する。
func NewBlockHandler(db *gorm.DB) *BlockHandler {
	return &BlockHandler{db: db}
}

type blockedUsersResponse struct {
	Blocked []publicUser `json:"blocked"`
}

// Block は :userId をブロックする（冪等）。ブロックは友達関係も解消する。
func (h *BlockHandler) Block(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	target := c.Param("userId")
	if target == me.ID {
		return echo.NewHTTPError(http.StatusBadRequest, "cannot block yourself")
	}
	err := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec(
			`insert into blocks (blocker_id, blocked_id) values (?, ?)
			 on conflict (blocker_id, blocked_id) do nothing`, me.ID, target,
		).Error; err != nil {
			return err
		}
		// ブロックすると友達関係は解消する（双方向）。
		return tx.Exec(
			`delete from friendships
			 where (requester_id = ? and receiver_id = ?)
			    or (requester_id = ? and receiver_id = ?)`,
			me.ID, target, target, me.ID,
		).Error
	})
	if err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.NoContent(http.StatusNoContent)
}

// Unblock は :userId のブロックを解除する（冪等）。
func (h *BlockHandler) Unblock(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	if err := h.db.Exec(
		`delete from blocks where blocker_id = ? and blocked_id = ?`,
		me.ID, c.Param("userId"),
	).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.NoContent(http.StatusNoContent)
}

// List は自分がブロックしたユーザー一覧を返す。
func (h *BlockHandler) List(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	type row struct {
		ID          string `gorm:"column:id"`
		Handle      string `gorm:"column:handle"`
		DisplayName string `gorm:"column:display_name"`
		Icon        string `gorm:"column:icon"`
	}
	var rows []row
	const q = `select u.id as id, u.user_id as handle,
	       u.display_name as display_name, u.icon as icon
from blocks b
join users u on u.id = b.blocked_id
where b.blocker_id = ?
order by b.created_at desc`
	if err := h.db.Raw(q, me.ID).Scan(&rows).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	blocked := make([]publicUser, 0, len(rows))
	for _, r := range rows {
		blocked = append(blocked, publicUser{ID: r.ID, UserID: r.Handle, DisplayName: r.DisplayName, Icon: r.Icon})
	}
	return c.JSON(http.StatusOK, blockedUsersResponse{Blocked: blocked})
}
