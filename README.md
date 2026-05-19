# Layer

> 場所への共感を、友達と積み重ねていく SNS

詳細は [`docs/require.md`](./docs/require.md)（要件定義）を参照。

## リポジトリ構成（モノレポ）

| ディレクトリ | 役割 | 技術 |
|---|---|---|
| [`mobile/`](./mobile) | モバイルアプリ | Flutter / Riverpod |
| [`frontend/`](./frontend) | Web フロントエンド | Next.js / TypeScript |
| [`backend/`](./backend) | API サーバー | Go / echo / gorm / PostgreSQL |
| [`docs/`](./docs) | 設計ドキュメント | — |

## セットアップ

各ディレクトリの `README.md` を参照。

```
mobile/   → Flutter SDK が必要
frontend/ → Node.js 20+ が必要
backend/  → Go 1.23+ と PostgreSQL が必要
```

## ドキュメント

- [要件定義](./docs/require.md)
- [データモデル](./docs/model/model.md)
- [画面設計・状態遷移](./docs/design/screens.md)
# layer
