package handler

import (
	"net/http"
	"os"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/cymed/layer/backend/internal/access"
	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"
)

// pinsPublic は公開モード（友達でない人の Pin も閲覧可）か。
// 既定は false（設計どおり友達限定）。PINS_PUBLIC=1/true で有効。
func pinsPublic() bool {
	v := os.Getenv("PINS_PUBLIC")
	return v == "1" || v == "true"
}

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

// pinRow は author 込みで Pin を取得する共通スキャン先。
type pinRow struct {
	ID                string    `gorm:"column:id"`
	UserID            string    `gorm:"column:user_id"`
	Body              string    `gorm:"column:body"`
	Lat               float64   `gorm:"column:lat"`
	Lng               float64   `gorm:"column:lng"`
	CreatedAt         time.Time `gorm:"column:created_at"`
	AuthorID          string    `gorm:"column:author_id"`
	AuthorUserID      string    `gorm:"column:author_user_id"`
	AuthorDisplayName string    `gorm:"column:author_display_name"`
	AuthorIcon        string    `gorm:"column:author_icon"`
}

func (r pinRow) toCreatedPin() createdPin {
	return createdPin{
		ID: r.ID, UserID: r.UserID, Body: r.Body, Lat: r.Lat, Lng: r.Lng, CreatedAt: r.CreatedAt,
		Author: pinAuthor{ID: r.AuthorID, UserID: r.AuthorUserID, DisplayName: r.AuthorDisplayName, Icon: r.AuthorIcon},
	}
}

// pinWithAuthorColumns は pins p ↔ users u を JOIN した select 句（lat/lng と author を展開）。
const pinWithAuthorColumns = `p.id as id, p.user_id as user_id, p.body as body,
	st_y(p.location::geometry) as lat, st_x(p.location::geometry) as lng,
	p.created_at as created_at,
	u.id as author_id, u.user_id as author_user_id,
	u.display_name as author_display_name, u.icon as author_icon`

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

type visiblePinsResponse struct {
	Pins []createdPin `json:"pins"`
}

// ListVisible は自分と accepted な友達の Pin を投稿者情報つきで返す
// （FR-4.2 / model.md §3.1 get_visible_pins 相当）。
func (h *PinHandler) ListVisible(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}

	var rows []pinRow
	var err error
	// 友達限定の条件: 明示的に scope=friends か、公開モードが無効なとき。
	// 公開モード(PINS_PUBLIC)かつ scope!=friends のときだけ全ユーザーを返す。
	if c.QueryParam("scope") == "friends" || !pinsPublic() {
		const q = `
with my_friends as (
  select case when requester_id = ? then receiver_id else requester_id end as friend_id
  from friendships
  where status = 'accepted' and (requester_id = ? or receiver_id = ?)
)
select ` + pinWithAuthorColumns + `
from pins p
join users u on u.id = p.user_id
where p.user_id = ? or p.user_id in (select friend_id from my_friends)
order by p.created_at desc`
		err = h.db.Raw(q, me.ID, me.ID, me.ID, me.ID).Scan(&rows).Error
	} else {
		const q = `select ` + pinWithAuthorColumns + `
from pins p
join users u on u.id = p.user_id
order by p.created_at desc`
		err = h.db.Raw(q).Scan(&rows).Error
	}
	if err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	pins := make([]createdPin, 0, len(rows))
	for _, r := range rows {
		pins = append(pins, r.toCreatedPin())
	}
	return c.JSON(http.StatusOK, visiblePinsResponse{Pins: pins})
}

// Delete は自分の Pin を削除する（owner のみ）。
// pin_discoveries は FK が NO ACTION のため先に消す。reactions は CASCADE。
func (h *PinHandler) Delete(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}
	id := c.Param("id")
	var ownerID string
	if err := h.db.Raw(`select user_id from pins where id = ?`, id).Scan(&ownerID).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	if ownerID == "" {
		return echo.NewHTTPError(http.StatusNotFound, "pin not found")
	}
	if ownerID != me.ID {
		return echo.NewHTTPError(http.StatusForbidden, "not allowed")
	}
	txErr := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec(
			`delete from pin_discoveries where pin_id = ? or triggered_by = ?`, id, id,
		).Error; err != nil {
			return err
		}
		return tx.Exec(`delete from pins where id = ?`, id).Error
	})
	if txErr != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, txErr.Error())
	}
	return c.NoContent(http.StatusNoContent)
}

// Get は Pin 詳細を返す（FR-5.1）。自分の Pin か IsFriend でなければ 403、無ければ 404。
func (h *PinHandler) Get(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}

	var r pinRow
	const q = `select ` + pinWithAuthorColumns + `
from pins p join users u on u.id = p.user_id
where p.id = ?`
	if err := h.db.Raw(q, c.Param("id")).Scan(&r).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	if r.ID == "" {
		return echo.NewHTTPError(http.StatusNotFound, "pin not found")
	}
	// 既定（友達限定）では自分か友達のみ。公開モードでは誰でも閲覧可。
	if !pinsPublic() && r.UserID != me.ID {
		friends, err := access.IsFriend(h.db, me.ID, r.UserID)
		if err != nil {
			return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
		}
		if !friends {
			return echo.NewHTTPError(http.StatusForbidden, "not allowed")
		}
	}
	return c.JSON(http.StatusOK, createPinResponse{Pin: r.toCreatedPin()})
}

// Nearby は基準 Pin の半径 20m 以内にある自分＋友達の Pin を返す（FR-5.2 / model.md §3.2）。
// 基準 Pin 自身は除外。基準 Pin が無ければ 404。
func (h *PinHandler) Nearby(c echo.Context) error {
	me := authmw.CurrentUser(c)
	if me == nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "unauthenticated")
	}

	id := c.Param("id")
	var baseID string
	if err := h.db.Raw(`select id from pins where id = ?`, id).Scan(&baseID).Error; err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	if baseID == "" {
		return echo.NewHTTPError(http.StatusNotFound, "pin not found")
	}

	var rows []pinRow
	var err error
	if pinsPublic() {
		// 公開モード: 同じ場所の全ユーザーの Pin。
		const q = `select ` + pinWithAuthorColumns + `
from pins p
join users u on u.id = p.user_id
where p.id <> ?
  and ST_DWithin(p.location, (select location from pins where id = ?), 20)
order by p.created_at desc`
		err = h.db.Raw(q, id, id).Scan(&rows).Error
	} else {
		// 既定: 自分 + accepted な友達のみ。
		const q = `
with my_friends as (
  select case when requester_id = ? then receiver_id else requester_id end as friend_id
  from friendships
  where status = 'accepted' and (requester_id = ? or receiver_id = ?)
)
select ` + pinWithAuthorColumns + `
from pins p
join users u on u.id = p.user_id
where p.id <> ?
  and ST_DWithin(p.location, (select location from pins where id = ?), 20)
  and (p.user_id = ? or p.user_id in (select friend_id from my_friends))
order by p.created_at desc`
		err = h.db.Raw(q, me.ID, me.ID, me.ID, id, id, me.ID).Scan(&rows).Error
	}
	if err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	pins := make([]createdPin, 0, len(rows))
	for _, r := range rows {
		pins = append(pins, r.toCreatedPin())
	}
	return c.JSON(http.StatusOK, visiblePinsResponse{Pins: pins})
}
