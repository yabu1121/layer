package handler

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

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

// findReceivedRequest は :id の申請を取得し、認証ユーザーが receiver であることを確認する。
// 申請が無ければ 404、receiver でなければ 403。
func (h *FriendHandler) findReceivedRequest(c echo.Context) (*model.User, *model.Friendship, error) {
	me := authmw.CurrentUser(c)
	if me == nil {
		return nil, nil, echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	var f model.Friendship
	if err := h.db.Where("id = ?", c.Param("id")).First(&f).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil, echo.NewHTTPError(http.StatusNotFound, "request not found")
		}
		return nil, nil, echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	if f.ReceiverID != me.ID {
		return nil, nil, echo.NewHTTPError(http.StatusForbidden, "only the receiver can act on this request")
	}
	return me, &f, nil
}

// Accept は受信した友達申請を承認する（FR-2.3 / US-A5）。receiver のみ可。
func (h *FriendHandler) Accept(c echo.Context) error {
	me, f, err := h.findReceivedRequest(c)
	if err != nil {
		return err
	}

	now := time.Now()
	if txErr := h.db.Transaction(func(tx *gorm.DB) error {
		f.Status = "accepted"
		f.AcceptedAt = &now
		if err := tx.Save(f).Error; err != nil {
			return err
		}
		// 申請者に friend_accepted 通知。
		payload, _ := json.Marshal(map[string]any{
			"userId":       me.ID,
			"handle":       me.UserID,
			"displayName":  me.DisplayName,
			"icon":         me.Icon,
			"friendshipId": f.ID,
		})
		return tx.Create(&model.Notification{
			UserID:  f.RequesterID,
			Kind:    "friend_accepted",
			Payload: string(payload),
		}).Error
	}); txErr != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, txErr.Error())
	}
	return c.JSON(http.StatusOK, echo.Map{"friendship": f})
}

// Reject は受信した友達申請を拒否する（FR-2.3）。receiver のみ可、通知は出さない。
func (h *FriendHandler) Reject(c echo.Context) error {
	_, f, err := h.findReceivedRequest(c)
	if err != nil {
		return err
	}
	f.Status = "rejected"
	if err := h.db.Save(f).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.NoContent(http.StatusNoContent)
}
