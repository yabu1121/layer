package handler

import (
	"net/http"

	"github.com/cymed/layer/backend/internal/model"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

// PinHandler は Pin 関連のエンドポイントを束ねる。
type PinHandler struct {
	db *gorm.DB
}

// NewPinHandler は PinHandler を生成する。
func NewPinHandler(db *gorm.DB) *PinHandler {
	return &PinHandler{db: db}
}

// List は Pin 一覧を返す（スタブ。FR-4.2: 友達＋自分の Pin に絞る実装は今後）。
func (h *PinHandler) List(c echo.Context) error {
	var pins []model.Pin
	if err := h.db.Order("created_at desc").Find(&pins).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, pins)
}

// Create は Pin を作成する（スタブ。認証ユーザーの紐付け・発見検知は今後）。
func (h *PinHandler) Create(c echo.Context) error {
	var pin model.Pin
	if err := c.Bind(&pin); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}
	if err := h.db.Create(&pin).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusCreated, pin)
}
