package router

import (
	"github.com/cymed/layer/backend/internal/handler"
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
	"gorm.io/gorm"
)

// New は echo インスタンスを構築し、ルーティングを登録して返す。
func New(db *gorm.DB) *echo.Echo {
	e := echo.New()

	e.Use(middleware.Logger())
	e.Use(middleware.Recover())
	e.Use(middleware.CORS())

	e.GET("/health", handler.Health)

	pin := handler.NewPinHandler(db)
	api := e.Group("/api")
	api.GET("/pins", pin.List)
	api.POST("/pins", pin.Create)

	return e
}
