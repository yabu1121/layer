package handler

import (
	"errors"
	"net/http"
	"regexp"
	"strings"
	"unicode/utf8"

	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/cymed/layer/backend/internal/model"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

// MeHandler は認証ユーザー自身のプロフィール関連エンドポイントを束ねる。
type MeHandler struct {
	db *gorm.DB
}

// NewMeHandler は MeHandler を生成する。
func NewMeHandler(db *gorm.DB) *MeHandler {
	return &MeHandler{db: db}
}

type meResponse struct {
	User model.User `json:"user"`
}

type updateProfileRequest struct {
	DisplayName string `json:"display_name"`
	Icon        string `json:"icon"`
	UserID      string `json:"user_id"`
}

// userIDPattern は表示用ハンドルの許可形式（FR-1.3）。
var userIDPattern = regexp.MustCompile(`^[a-zA-Z0-9_]{3,20}$`)

// maxIconRunes は icon の符号位置数の上限。1 つの絵文字（ZWJ シーケンス・
// 肌色・国旗を含む）を許容しつつ巨大文字列を弾く余裕を持たせた値。
const maxIconRunes = 16

// Get は認証ユーザー自身を返す（FR-1.4 / US-A8）。
func (h *MeHandler) Get(c echo.Context) error {
	user := authmw.CurrentUser(c)
	if user == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	return c.JSON(http.StatusOK, meResponse{User: *user})
}

// UpdateProfile は表示名・アイコン・ハンドルを更新する（FR-1.2 / FR-1.3 / FR-1.4）。
func (h *MeHandler) UpdateProfile(c echo.Context) error {
	user := authmw.CurrentUser(c)
	if user == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}

	var req updateProfileRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}
	req.DisplayName = strings.TrimSpace(req.DisplayName)
	req.Icon = strings.TrimSpace(req.Icon)
	if msg := validateProfile(req); msg != "" {
		return echo.NewHTTPError(http.StatusBadRequest, msg)
	}

	user.DisplayName = req.DisplayName
	user.Icon = req.Icon
	user.UserID = req.UserID
	if err := h.db.Save(user).Error; err != nil {
		// user_id は一意。重複は 409 で返す。
		if isUniqueViolation(err) {
			return c.JSON(http.StatusConflict, echo.Map{"error": "user_id_taken"})
		}
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, meResponse{User: *user})
}

// validateProfile は更新リクエストを検証し、問題があればメッセージを返す。
// display_name / icon は呼び出し側で trim 済みであることを前提とする。
func validateProfile(req updateProfileRequest) string {
	if n := utf8.RuneCountInString(req.DisplayName); n < 1 || n > 20 {
		return "display_name must be 1-20 characters"
	}
	if msg := validateIcon(req.Icon); msg != "" {
		return msg
	}
	if !userIDPattern.MatchString(req.UserID) {
		return "user_id must match ^[a-zA-Z0-9_]{3,20}$"
	}
	return ""
}

// validateIcon は icon が 1 つの絵文字らしいかを軽量に検証する。
// 完全な絵文字判定はクライアントの絵文字ピッカー（FR-1.2）に委ね、サーバでは
// 「非空」「上限符号位置数」「非 ASCII を含む（プレーンテキスト排除）」を担保する。
func validateIcon(icon string) string {
	n := utf8.RuneCountInString(icon)
	if n < 1 {
		return "icon is required"
	}
	if n > maxIconRunes {
		return "icon must be a single emoji"
	}
	for _, r := range icon {
		if r > 0x7F {
			return ""
		}
	}
	return "icon must be an emoji"
}

// isUniqueViolation は PostgreSQL の一意制約違反（SQLSTATE 23505）かを判定する。
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
