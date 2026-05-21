package handler

import (
	"errors"
	"net/http"

	"github.com/cymed/layer/backend/internal/model"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

// UserHandler はユーザー検索などのエンドポイントを束ねる。
type UserHandler struct {
	db *gorm.DB
}

// NewUserHandler は UserHandler を生成する。
func NewUserHandler(db *gorm.DB) *UserHandler {
	return &UserHandler{db: db}
}

// publicUser は他ユーザーに見せてよい最小プロフィール（require.md §6.2: 露出最小化）。
// created_at 等は含めない。id は友達申請（#21）で相手を参照するため残す。
type publicUser struct {
	ID          string `json:"id"`
	UserID      string `json:"userId"`
	DisplayName string `json:"displayName"`
	Icon        string `json:"icon"`
}

func toPublicUser(u model.User) publicUser {
	return publicUser{ID: u.ID, UserID: u.UserID, DisplayName: u.DisplayName, Icon: u.Icon}
}

type userResponse struct {
	User publicUser `json:"user"`
}

// Search は user_id の完全一致でユーザーを 1 件返す（FR-2.1 / US-A4）。
// 友達追加の入口。自分自身もヒットさせ、表示はクライアントに委ねる。
// 非友達にも返るため、公開プロフィール（publicUser）に絞って返す。
func (h *UserHandler) Search(c echo.Context) error {
	userID := c.QueryParam("user_id")
	if userID == "" {
		return echo.NewHTTPError(http.StatusBadRequest, "user_id is required")
	}

	var user model.User
	if err := h.db.Where("user_id = ?", userID).First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return echo.NewHTTPError(http.StatusNotFound, "user not found")
		}
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, userResponse{User: toPublicUser(user)})
}
