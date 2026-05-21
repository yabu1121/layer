package handler

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/cymed/layer/backend/internal/access"
	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/cymed/layer/backend/internal/model"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

// FriendHandler は友達関係のエンドポイントを束ねる（本イシューでは申請送信のみ）。
type FriendHandler struct {
	db *gorm.DB
}

// NewFriendHandler は FriendHandler を生成する。
func NewFriendHandler(db *gorm.DB) *FriendHandler {
	return &FriendHandler{db: db}
}

type friendRequestRequest struct {
	ReceiverID string `json:"receiver_id"`
}

type friendRequestResponse struct {
	Request model.Friendship `json:"request"`
}

// 申請を中断して 409 に変換するためのセンチネルエラー（トランザクションを巻き戻す）。
var (
	errAlreadyRequested = errors.New("already_requested")
	errAlreadyFriends   = errors.New("already_friends")
)

// SendRequest は友達申請を送る（FR-2.2 / US-A3）。
// 既存の rejected 行は pending に戻す。重複・自分宛は 409 / 400。
func (h *FriendHandler) SendRequest(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	var req friendRequestRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}
	if req.ReceiverID == "" {
		return echo.NewHTTPError(http.StatusBadRequest, "receiver_id is required")
	}
	if req.ReceiverID == me.ID {
		return echo.NewHTTPError(http.StatusBadRequest, "cannot send a request to yourself")
	}

	// 宛先ユーザーの存在確認。
	if err := h.db.Where("id = ?", req.ReceiverID).First(&model.User{}).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return echo.NewHTTPError(http.StatusNotFound, "user not found")
		}
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	// すでに友達（双方向 accepted）なら申請不可。
	if friends, err := access.IsFriend(h.db, me.ID, req.ReceiverID); err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	} else if friends {
		return c.JSON(http.StatusConflict, echo.Map{"error": "already_friends"})
	}

	var result model.Friendship
	err := h.db.Transaction(func(tx *gorm.DB) error {
		// 自分発信の既存行（unique: requester_id + receiver_id）。
		var existing model.Friendship
		findErr := tx.Where("requester_id = ? and receiver_id = ?", me.ID, req.ReceiverID).First(&existing).Error
		switch {
		case findErr == nil:
			switch existing.Status {
			case "pending":
				return errAlreadyRequested
			case "accepted":
				return errAlreadyFriends
			default: // rejected → pending に復活
				existing.Status = "pending"
				if err := tx.Save(&existing).Error; err != nil {
					return err
				}
				result = existing
			}
		case errors.Is(findErr, gorm.ErrRecordNotFound):
			result = model.Friendship{RequesterID: me.ID, ReceiverID: req.ReceiverID, Status: "pending"}
			if err := tx.Create(&result).Error; err != nil {
				return err
			}
		default:
			return findErr
		}

		// 宛先に friend_request 通知を作る。
		payload, _ := json.Marshal(map[string]any{
			"userId":      me.ID,
			"handle":      me.UserID,
			"displayName": me.DisplayName,
			"icon":        me.Icon,
			"requestId":   result.ID,
		})
		return tx.Create(&model.Notification{
			UserID:  req.ReceiverID,
			Kind:    "friend_request",
			Payload: string(payload),
		}).Error
	})

	switch {
	case errors.Is(err, errAlreadyRequested):
		return c.JSON(http.StatusConflict, echo.Map{"error": "already_requested"})
	case errors.Is(err, errAlreadyFriends):
		return c.JSON(http.StatusConflict, echo.Map{"error": "already_friends"})
	case err != nil:
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusCreated, friendRequestResponse{Request: result})
}
