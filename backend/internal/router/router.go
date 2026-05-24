package router

import (
	"os"
	"strings"

	"github.com/cymed/layer/backend/internal/handler"
	authmw "github.com/cymed/layer/backend/internal/middleware"
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
	"gorm.io/gorm"
)

// maxBodyBytes は API リクエストボディの上限。画像は presigned で R2 へ直接
// アップロードするため、API 本体は小さくてよい。
const maxBodyBytes = "1M"

// corsConfig は CORS 設定を返す。env ALLOWED_ORIGINS（カンマ区切り）があれば
// そのオリジンのみ許可し、未設定なら開発用に全許可（"*"）にフォールバックする。
func corsConfig() middleware.CORSConfig {
	cfg := middleware.DefaultCORSConfig
	cfg.AllowHeaders = []string{echo.HeaderOrigin, echo.HeaderContentType, echo.HeaderAuthorization}
	var allow []string
	for _, o := range strings.Split(os.Getenv("ALLOWED_ORIGINS"), ",") {
		if s := strings.TrimSpace(o); s != "" {
			allow = append(allow, s)
		}
	}
	if len(allow) > 0 {
		cfg.AllowOrigins = allow
	}
	return cfg
}

// New は echo インスタンスを構築し、ルーティングを登録して返す。
// verify は ID トークン検証関数（本番は Google、テストはスタブを渡す）。
func New(db *gorm.DB, verify authmw.VerifyFunc) *echo.Echo {
	e := echo.New()

	e.Use(middleware.RequestID())
	// アクセスログ。Authorization 等の機密ヘッダは出さない（id/method/uri/status のみ）。
	e.Use(middleware.LoggerWithConfig(middleware.LoggerConfig{
		Format: "${time_rfc3339} id=${id} ${method} ${uri} ${status} ${latency_human}\n",
	}))
	e.Use(middleware.Recover())
	e.Use(middleware.Secure())                // セキュリティヘッダ（nosniff / frame deny 等）
	e.Use(middleware.BodyLimit(maxBodyBytes)) // 過大ボディ防止
	e.Use(middleware.CORSWithConfig(corsConfig()))

	// /health は認証不要。
	e.GET("/health", handler.Health)

	pin := handler.NewPinHandler(db)
	auth := handler.NewAuthHandler(db, verify)
	me := handler.NewMeHandler(db)
	user := handler.NewUserHandler(db)
	friend := handler.NewFriendHandler(db)
	reaction := handler.NewReactionHandler(db)
	comment := handler.NewCommentHandler(db)
	notification := handler.NewNotificationHandler(db)

	// /api/* は認証必須。サインイン／サインアウトは認証前に叩くため除外する。
	api := e.Group("/api")
	api.Use(authmw.RequireAuth(db, verify, "/api/auth/sign-in", "/api/auth/sign-out"))
	api.POST("/auth/sign-in", auth.SignIn)
	api.POST("/auth/sign-out", auth.SignOut)
	api.GET("/me", me.Get)
	api.POST("/me/profile", me.UpdateProfile)
	api.POST("/me/location", me.UpdateLocation)
	api.GET("/locations", me.ListOthersLocations)
	api.GET("/users/search", user.Search)
	api.GET("/friends", friend.ListFriends)
	api.DELETE("/friends/:userId", friend.Unfriend)
	api.POST("/friends/requests", friend.SendRequest)
	api.GET("/friends/requests/incoming", friend.ListIncoming)
	api.POST("/friends/requests/:id/accept", friend.Accept)
	api.POST("/friends/requests/:id/reject", friend.Reject)
	api.GET("/pins", pin.List)
	api.GET("/pins/visible", pin.ListVisible)
	api.GET("/pins/:id", pin.Get)
	api.GET("/pins/:id/nearby", pin.Nearby)
	api.POST("/pins", pin.Create)
	api.DELETE("/pins/:id", pin.Delete)
	api.GET("/pins/:id/reactions", reaction.List)
	api.POST("/pins/:id/reactions", reaction.Create)
	api.DELETE("/pins/:id/reactions/me", reaction.DeleteMine)
	api.GET("/pins/:id/comments", comment.List)
	api.POST("/pins/:id/comments", comment.Create)
	api.DELETE("/pins/:id/comments/:commentId", comment.DeleteMine)
	api.GET("/notifications", notification.List)
	api.POST("/notifications/read-all", notification.ReadAll)
	api.GET("/notifications/unread-count", notification.UnreadCount)

	return e
}
