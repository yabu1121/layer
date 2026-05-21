package handler

import (
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	authmw "github.com/cymed/layer/backend/internal/middleware"
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

// createPinRequest は POST /api/pins のリクエスト。投稿者は認証ユーザー。
// 位置は lat/lng で受け取り、DB では geography に変換して保存する。
// 未指定と 0 を区別するため lat/lng はポインタにする。
type createPinRequest struct {
	Body string   `json:"body"`
	Lat  *float64 `json:"lat"`
	Lng  *float64 `json:"lng"`
}

// pinAuthor は Pin 投稿者の公開プロフィール。
type pinAuthor struct {
	ID          string `json:"id"`
	UserID      string `json:"userId"`
	DisplayName string `json:"displayName"`
	Icon        string `json:"icon"`
}

// createdPin は投稿直後の Pin（lat/lng と author を含む）。
type createdPin struct {
	ID        string    `json:"id"`
	UserID    string    `json:"userId"`
	Body      string    `json:"body"`
	Lat       float64   `json:"lat"`
	Lng       float64   `json:"lng"`
	CreatedAt time.Time `json:"createdAt"`
	Author    pinAuthor `json:"author"`
}

type createPinResponse struct {
	Pin createdPin `json:"pin"`
}

// pinResponse は Pin の API レスポンス。geography の location は lat/lng に
// 展開して返し、JSON 上の契約は移行前と変えない。
type pinResponse struct {
	ID        string    `json:"id"`
	UserID    string    `json:"userId"`
	Body      string    `json:"body"`
	Lat       float64   `json:"lat"`
	Lng       float64   `json:"lng"`
	CreatedAt time.Time `json:"createdAt"`
}

// location を lat/lng に展開する共通の select 句。geography を geometry に
// キャストして ST_X(経度)/ST_Y(緯度) を取り出す。
const pinSelectColumns = `id, user_id, body,
	st_y(location::geometry) as lat,
	st_x(location::geometry) as lng,
	created_at`

// List は Pin 一覧を返す（スタブ。FR-4.2: 友達＋自分の Pin に絞る実装は今後）。
func (h *PinHandler) List(c echo.Context) error {
	pins := []pinResponse{}
	q := `select ` + pinSelectColumns + ` from pins order by created_at desc`
	if err := h.db.Raw(q).Scan(&pins).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, pins)
}

// Create は認証ユーザーの Pin を作成する（FR-3）。INSERT 後に発見検知トリガー
// （003）が同一トランザクションで起動する。
func (h *PinHandler) Create(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}

	var req createPinRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}
	body := strings.TrimSpace(req.Body)
	if n := utf8.RuneCountInString(body); n < 1 || n > 200 {
		return echo.NewHTTPError(http.StatusBadRequest, "body must be 1-200 characters")
	}
	if req.Lat == nil || req.Lng == nil {
		return echo.NewHTTPError(http.StatusBadRequest, "lat and lng are required")
	}
	if *req.Lat < -90 || *req.Lat > 90 || *req.Lng < -180 || *req.Lng > 180 {
		return echo.NewHTTPError(http.StatusBadRequest, "lat must be within [-90,90] and lng within [-180,180]")
	}

	// ST_MakePoint は (経度, 緯度) の順。created_at は raw insert のため now() で明示。
	const q = `insert into pins (user_id, body, location, created_at)
		values (?, ?, st_setsrid(st_makepoint(?, ?), 4326)::geography, now())
		returning id, st_y(location::geometry) as lat, st_x(location::geometry) as lng, created_at`
	var row struct {
		ID        string
		Lat       float64
		Lng       float64
		CreatedAt time.Time
	}
	if err := h.db.Raw(q, me.ID, body, *req.Lng, *req.Lat).Scan(&row).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	return c.JSON(http.StatusCreated, createPinResponse{Pin: createdPin{
		ID:        row.ID,
		UserID:    me.ID,
		Body:      body,
		Lat:       row.Lat,
		Lng:       row.Lng,
		CreatedAt: row.CreatedAt,
		Author:    pinAuthor{ID: me.ID, UserID: me.UserID, DisplayName: me.DisplayName, Icon: me.Icon},
	}})
}
