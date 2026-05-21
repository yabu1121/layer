package handler

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"net/http"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/cymed/layer/backend/internal/model"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

// AuthHandler はサインイン関連のエンドポイントを束ねる。
type AuthHandler struct {
	db     *gorm.DB
	verify authmw.VerifyFunc
	// newUserID は仮ハンドルの採番関数。テストで衝突を再現できるよう差し替え可能にする。
	newUserID func() string
}

// NewAuthHandler は AuthHandler を生成する。verify は ID トークン検証関数。
func NewAuthHandler(db *gorm.DB, verify authmw.VerifyFunc) *AuthHandler {
	return &AuthHandler{db: db, verify: verify, newUserID: defaultUserID}
}

type signInRequest struct {
	IDToken string `json:"id_token"`
}

type signInResponse struct {
	User  model.User `json:"user"`
	IsNew bool       `json:"is_new"`
}

// SignIn は ID トークンを検証し、対応するユーザーを upsert する。
// 既存なら is_new=false、未登録なら新規作成して is_new=true を返す（FR-1.1 / FR-1.3）。
func (h *AuthHandler) SignIn(c echo.Context) error {
	var req signInRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}
	sub, err := h.verify(c.Request().Context(), req.IDToken)
	if err != nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "invalid token")
	}

	// 既存ユーザーを優先する。
	var user model.User
	if err := h.db.Where("auth_uid = ?", sub).First(&user).Error; err == nil {
		return c.JSON(http.StatusOK, signInResponse{User: user, IsNew: false})
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	// 未登録: 仮の user_id を採番して新規作成する。表示名・アイコンは
	// オンボーディング（#32）で設定するため空で作る。
	// - user_id 衝突: 採番し直してリトライ。
	// - auth_uid 衝突: 並行サインインで先に作成された → 既存を取得して is_new=false。
	const maxAttempts = 5
	for range maxAttempts {
		candidate := model.User{
			UserID:       h.newUserID(),
			AuthProvider: "google",
			AuthUID:      sub,
		}
		if err := h.db.Create(&candidate).Error; err == nil {
			return c.JSON(http.StatusOK, signInResponse{User: candidate, IsNew: true})
		}
		var existing model.User
		if h.db.Where("auth_uid = ?", sub).First(&existing).Error == nil {
			return c.JSON(http.StatusOK, signInResponse{User: existing, IsNew: false})
		}
		// auth_uid は未登録 → user_id 衝突とみなし、次の候補で再試行する。
	}
	return echo.NewHTTPError(http.StatusInternalServerError, "failed to allocate user id")
}

// SignOut はサーバ側状態を持たないため 204 を返すのみ（クライアントが Bearer を破棄する）。
func (h *AuthHandler) SignOut(c echo.Context) error {
	return c.NoContent(http.StatusNoContent)
}

// defaultUserID は仮の表示用ハンドル user_<short hex> を採番する。
// オンボーディングでユーザーが変更できる（FR-1.3）。
func defaultUserID() string {
	b := make([]byte, 4)
	_, _ = rand.Read(b)
	return "user_" + hex.EncodeToString(b)
}
