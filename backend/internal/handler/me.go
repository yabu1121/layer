package handler

import (
	"errors"
	"net/http"
	"regexp"
	"strings"
	"time"
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

// --- 現在地（点表示）---

type updateLocationRequest struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

// UpdateLocation は自分の現在地を更新する（点表示用）。
func (h *MeHandler) UpdateLocation(c echo.Context) error {
	user := authmw.CurrentUser(c)
	if user == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	var req updateLocationRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}
	now := time.Now()
	if err := h.db.Model(&model.User{}).Where("id = ?", user.ID).Updates(map[string]any{
		"last_lat":         req.Lat,
		"last_lng":         req.Lng,
		"last_location_at": now,
	}).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.NoContent(http.StatusNoContent)
}

type userLocation struct {
	UserID string  `json:"userId"`
	Lat    float64 `json:"lat"`
	Lng    float64 `json:"lng"`
}

type locationsResponse struct {
	Locations []userLocation `json:"locations"`
}

// ListOthersLocations は accepted な友達で位置を報告済みのユーザーの現在地を返す
// （点表示用）。require.md §6.2「友達以外への露出ゼロ」に従い友達限定。
func (h *MeHandler) ListOthersLocations(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	type row struct {
		ID  string
		Lat float64
		Lng float64
	}
	var rows []row
	// accepted な友達（双方向）かつ位置報告済みのユーザーのみ。
	const q = `select u.id as id, u.last_lat as lat, u.last_lng as lng
from users u
join friendships f
  on f.status = 'accepted'
 and ((f.requester_id = ? and f.receiver_id = u.id)
   or (f.receiver_id = ? and f.requester_id = u.id))
where u.id <> ? and u.last_lat is not null and u.last_lng is not null`
	if err := h.db.Raw(q, me.ID, me.ID, me.ID).Scan(&rows).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	locs := make([]userLocation, 0, len(rows))
	for _, r := range rows {
		locs = append(locs, userLocation{UserID: r.ID, Lat: r.Lat, Lng: r.Lng})
	}
	return c.JSON(http.StatusOK, locationsResponse{Locations: locs})
}

// Delete は自分のアカウントと関連レコードを全削除する（require.md §9.3。
// App Store のアカウント削除要件）。FK 順序に注意してトランザクションで消す。
func (h *MeHandler) Delete(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	id := me.ID
	err := h.db.Transaction(func(tx *gorm.DB) error {
		// 自分が他人の Pin に付けた反応・コメント（pin 経由の cascade では消えない）。
		if err := tx.Exec(`delete from reactions where user_id = ?`, id).Error; err != nil {
			return err
		}
		if err := tx.Exec(`delete from comments where user_id = ?`, id).Error; err != nil {
			return err
		}
		// 発見ログ（自分が発見した / 自分の Pin が絡むもの）。FK cascade なしのため先に消す。
		if err := tx.Exec(`delete from pin_discoveries
			where user_id = ?
			   or pin_id in (select id from pins where user_id = ?)
			   or triggered_by in (select id from pins where user_id = ?)`, id, id, id).Error; err != nil {
			return err
		}
		// 友達関係（双方向）。
		if err := tx.Exec(`delete from friendships where requester_id = ? or receiver_id = ?`, id, id).Error; err != nil {
			return err
		}
		// 自分宛の通知。
		if err := tx.Exec(`delete from notifications where user_id = ?`, id).Error; err != nil {
			return err
		}
		// 自分の Pin（その Pin への reactions / comments は FK cascade で消える）。
		if err := tx.Exec(`delete from pins where user_id = ?`, id).Error; err != nil {
			return err
		}
		// 最後に本人。
		return tx.Exec(`delete from users where id = ?`, id).Error
	})
	if err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.NoContent(http.StatusNoContent)
}
