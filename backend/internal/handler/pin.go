package handler

import (
	"net/http"
	"time"

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

// createPinRequest は POST /api/pins のリクエスト。
// 位置は引き続き lat/lng で受け取り、DB では geography に変換して保存する。
// userId は認証導入（#16/#18）までの暫定。確定後はトークンから解決する。
type createPinRequest struct {
	UserID string  `json:"userId"`
	Body   string  `json:"body"`
	Lat    float64 `json:"lat"`
	Lng    float64 `json:"lng"`
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

// Create は Pin を作成する（スタブ。認証ユーザーの紐付け・発見検知は今後）。
func (h *PinHandler) Create(c echo.Context) error {
	var req createPinRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}

	// ST_MakePoint は (経度, 緯度) の順であることに注意（model.md §3.2 と同じ）。
	// created_at は gorm の自動付与を経由しない raw insert のため now() で明示する
	// （カラムに DB デフォルトは無い）。
	q := `insert into pins (user_id, body, location, created_at)
		values (?, ?, st_setsrid(st_makepoint(?, ?), 4326)::geography, now())
		returning ` + pinSelectColumns
	var res pinResponse
	if err := h.db.Raw(q, req.UserID, req.Body, req.Lng, req.Lat).Scan(&res).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusCreated, res)
}
