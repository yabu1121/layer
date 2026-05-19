# backend

Layer の API サーバー。Go + echo + gorm + PostgreSQL。

## 必要なもの

- Go 1.23+
- PostgreSQL 15+（PostGIS 拡張）

## セットアップ

```bash
cd backend
cp .env.example .env        # DATABASE_URL などを設定
go mod tidy                 # 依存解決（go.mod の require が埋まる）
go run ./cmd/server         # 起動 → http://localhost:8080/health
```

## 構成

```
backend/
├── cmd/server/main.go        エントリポイント
├── internal/
│   ├── config/               設定読み込み（.env）
│   ├── database/             DB 接続・マイグレーション
│   ├── model/                テーブル定義（docs/model/model.md と対応）
│   ├── handler/              HTTP ハンドラ
│   └── router/               ルーティング
└── .env.example
```

## エンドポイント（現状スタブ）

| メソッド | パス | 内容 |
|---|---|---|
| GET | `/health` | ヘルスチェック |
| GET | `/api/pins` | Pin 一覧 |
| POST | `/api/pins` | Pin 作成 |

## 補足

- PostGIS の `geography` 型・地理空間インデックス・発見検知トリガーは
  gorm の AutoMigrate では扱えないため、SQL マイグレーションで別途管理する
  （`docs/model/model.md` §3〜§5 を参照）。
- デプロイ先は Cloudflare を想定。
