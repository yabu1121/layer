package router

import (
	"github.com/cymed/layer/backend/internal/handler"
	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
	"gorm.io/gorm"
)

// New は echo インスタンスを構築し、ルーティングを登録して返す。
// verify は ID トークン検証関数（本番は Google、テストはスタブを渡す）。
func New(db *gorm.DB, verify authmw.VerifyFunc) *echo.Echo {
	e := echo.New()

	e.Use(middleware.Logger())
	e.Use(middleware.Recover())
	e.Use(middleware.CORS())

	// /health は認証不要。
	e.GET("/health", handler.Health)

	pin := handler.NewPinHandler(db)

	// /api/* は認証必須。サインイン（#18 で追加予定）は除外する。
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, verify, "/api/auth/sign-in"))
	api.GET("/pins", pin.List)
	api.POST("/pins", pin.Create)

	return e
}
