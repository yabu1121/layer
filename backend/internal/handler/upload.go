package handler

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/labstack/echo/v4"
)

// r2Config は Cloudflare R2（S3 互換）への接続設定。env から読む。
type r2Config struct {
	AccountID  string
	Bucket     string
	AccessKey  string
	SecretKey  string
	PublicBase string
}

func (c r2Config) configured() bool {
	return c.AccountID != "" && c.Bucket != "" &&
		c.AccessKey != "" && c.SecretKey != "" && c.PublicBase != ""
}

// UploadHandler は画像アップロード用 presigned URL 発行を担う（US-B3）。
type UploadHandler struct {
	cfg r2Config
}

// NewUploadHandler は env から R2 設定を読んで生成する。
func NewUploadHandler() *UploadHandler {
	return &UploadHandler{cfg: r2Config{
		AccountID:  os.Getenv("R2_ACCOUNT_ID"),
		Bucket:     os.Getenv("R2_BUCKET"),
		AccessKey:  os.Getenv("R2_ACCESS_KEY_ID"),
		SecretKey:  os.Getenv("R2_SECRET_ACCESS_KEY"),
		PublicBase: os.Getenv("R2_PUBLIC_BASE_URL"),
	}}
}

// allowedImageTypes は許可する Content-Type → 拡張子。
var allowedImageTypes = map[string]string{
	"image/jpeg": "jpg",
	"image/png":  "png",
	"image/webp": "webp",
}

type presignRequest struct {
	ContentType string `json:"contentType"`
}

type presignResponse struct {
	UploadURL string `json:"uploadUrl"` // R2 への PUT 用 presigned URL
	PublicURL string `json:"publicUrl"` // 公開取得 URL（Pin の image_url に保存）
}

// PresignPinImage は Pin 画像アップロード用の presigned PUT URL を返す。
// クライアントは uploadUrl に画像を PUT し、publicUrl を POST /api/pins の
// image_url として送る。R2 未設定なら 503。
func (h *UploadHandler) PresignPinImage(c echo.Context) error {
	if !h.cfg.configured() {
		return echo.NewHTTPError(http.StatusServiceUnavailable, "image upload not configured")
	}
	var req presignRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, "invalid body")
	}
	ext, ok := allowedImageTypes[strings.ToLower(strings.TrimSpace(req.ContentType))]
	if !ok {
		return echo.NewHTTPError(http.StatusBadRequest, "unsupported content type")
	}
	key := "pin-images/" + randomHex(16) + "." + ext

	client := s3.New(s3.Options{
		Region:       "auto",
		BaseEndpoint: aws.String("https://" + h.cfg.AccountID + ".r2.cloudflarestorage.com"),
		Credentials: credentials.NewStaticCredentialsProvider(
			h.cfg.AccessKey, h.cfg.SecretKey, ""),
	})
	out, err := s3.NewPresignClient(client).PresignPutObject(
		c.Request().Context(),
		&s3.PutObjectInput{
			Bucket:      aws.String(h.cfg.Bucket),
			Key:         aws.String(key),
			ContentType: aws.String(req.ContentType),
		},
		s3.WithPresignExpires(10*time.Minute),
	)
	if err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}
	return c.JSON(http.StatusOK, presignResponse{
		UploadURL: out.URL,
		PublicURL: strings.TrimRight(h.cfg.PublicBase, "/") + "/" + key,
	})
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
