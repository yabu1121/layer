package handler

import (
	"encoding/json"
	"net/http"

	"github.com/cymed/layer/backend/internal/access"
	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/cymed/layer/backend/internal/model"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

// ReactionHandler は「わかる」リアクションのエンドポイントを束ねる。
type ReactionHandler struct {
	db *gorm.DB
}

// NewReactionHandler は ReactionHandler を生成する。
func NewReactionHandler(db *gorm.DB) *ReactionHandler {
	return &ReactionHandler{db: db}
}

const reactionKind = "wakaru"

type reactionResponse struct {
	Reaction model.Reaction `json:"reaction"`
}

type reactionItem struct {
	ID   string     `json:"id"`
	User publicUser `json:"user"`
}

type reactionsResponse struct {
	Reactions []reactionItem `json:"reactions"`
}

// authorizePin は :id の Pin の owner を返す。Pin が無ければ 404、
// 自分の Pin でも友達の Pin でもなければ 403（require.md §6.2）。
func (h *ReactionHandler) authorizePin(c echo.Context, me *model.User) (ownerID string, err error) {
	if err := h.db.Raw(`select user_id from pins where id = ?`, c.Param("id")).Scan(&ownerID).Error; err != nil {
		return "", echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	if ownerID == "" {
		return "", echo.NewHTTPError(http.StatusNotFound, "pin not found")
	}
	if ownerID != me.ID {
		friends, ferr := access.IsFriend(h.db, me.ID, ownerID)
		if ferr != nil {
			return "", echo.NewHTTPError(http.StatusInternalServerError, ferr.Error())
		}
		if !friends {
			return "", echo.NewHTTPError(http.StatusForbidden, "not allowed")
		}
	}
	return ownerID, nil
}

// Create は対象 Pin に「わかる」を付ける（FR-5.3 / US-C2）。
// 二度押しは 409。owner（自分以外）に reaction 通知を作る。
func (h *ReactionHandler) Create(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	ownerID, authErr := h.authorizePin(c, me)
	if authErr != nil {
		return authErr
	}

	reaction := model.Reaction{PinID: c.Param("id"), UserID: me.ID, Kind: reactionKind}
	txErr := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&reaction).Error; err != nil {
			return err
		}
		if ownerID == me.ID {
			return nil // 自分の Pin への反応は自分宛通知を作らない
		}
		payload, _ := json.Marshal(map[string]any{
			"userId":      me.ID,
			"handle":      me.UserID,
			"displayName": me.DisplayName,
			"icon":        me.Icon,
			"pinId":       c.Param("id"),
			"reactionId":  reaction.ID,
		})
		return tx.Create(&model.Notification{
			UserID:  ownerID,
			Kind:    "reaction",
			Payload: string(payload),
		}).Error
	})
	if isUniqueViolation(txErr) {
		return c.JSON(http.StatusConflict, echo.Map{"error": "already_reacted"})
	}
	if txErr != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, txErr.Error())
	}
	return c.JSON(http.StatusCreated, reactionResponse{Reaction: reaction})
}

// DeleteMine は自分のリアクションを取り消す（冪等。無くても 204）。
func (h *ReactionHandler) DeleteMine(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	if _, authErr := h.authorizePin(c, me); authErr != nil {
		return authErr
	}
	if err := h.db.Exec(
		`delete from reactions where pin_id = ? and user_id = ? and kind = ?`,
		c.Param("id"), me.ID, reactionKind,
	).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.NoContent(http.StatusNoContent)
}

// List は対象 Pin のリアクション一覧を反応したユーザーつきで返す（FR-5.4）。
func (h *ReactionHandler) List(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	if _, authErr := h.authorizePin(c, me); authErr != nil {
		return authErr
	}

	type row struct {
		ID          string `gorm:"column:id"`
		UserID      string `gorm:"column:user_id"`
		Handle      string `gorm:"column:handle"`
		DisplayName string `gorm:"column:display_name"`
		Icon        string `gorm:"column:icon"`
	}
	var rows []row
	const q = `
select r.id as id, u.id as user_id, u.user_id as handle,
       u.display_name as display_name, u.icon as icon
from reactions r
join users u on u.id = r.user_id
where r.pin_id = ?
order by r.created_at desc`
	if err := h.db.Raw(q, c.Param("id")).Scan(&rows).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	reactions := make([]reactionItem, 0, len(rows))
	for _, r := range rows {
		reactions = append(reactions, reactionItem{
			ID:   r.ID,
			User: publicUser{ID: r.UserID, UserID: r.Handle, DisplayName: r.DisplayName, Icon: r.Icon},
		})
	}
	return c.JSON(http.StatusOK, reactionsResponse{Reactions: reactions})
}
