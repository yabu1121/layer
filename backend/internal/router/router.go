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
	auth := handler.NewAuthHandler(db, verify)
	me := handler.NewMeHandler(db)
	user := handler.NewUserHandler(db)
	friend := handler.NewFriendHandler(db)

	// /api/* は認証必須。サインイン／サインアウトは認証前に叩くため除外する。
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, verify, "/api/auth/sign-in", "/api/auth/sign-out"))
	api.POST("/auth/sign-in", auth.SignIn)
	api.POST("/auth/sign-out", auth.SignOut)
	api.GET("/me", me.Get)
	api.POST("/me/profile", me.UpdateProfile)
	api.GET("/users/search", user.Search)
	api.GET("/friends", friend.ListFriends)
	api.POST("/friends/requests", friend.SendRequest)
	api.GET("/friends/requests/incoming", friend.ListIncoming)
	api.POST("/friends/requests/:id/accept", friend.Accept)
	api.POST("/friends/requests/:id/reject", friend.Reject)
	api.GET("/pins", pin.List)
	api.GET("/pins/visible", pin.ListVisible)
	api.GET("/pins/:id", pin.Get)
	api.GET("/pins/:id/nearby", pin.Nearby)
	api.POST("/pins", pin.Create)

	return e
}
