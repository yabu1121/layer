# mobile

Layer のモバイルアプリ。Flutter + Riverpod。

## 必要なもの

- Flutter SDK 3.24+（`flutter doctor` がグリーン）
- Android SDK / Xcode（実機・エミュレータ用）

## セットアップ

このディレクトリには `pubspec.yaml` と `lib/` のみが置かれている。
プラットフォーム固有のフォルダ（`android/` `ios/` など）は Flutter CLI で生成する。

```bash
cd mobile
flutter create .            # android/ ios/ 等を生成（既存の pubspec.yaml と lib/ は保持される）
cp .env.example .env        # API_BASE_URL などを設定
flutter pub get             # 依存解決
flutter run                 # 実行
```

## 構成

```
mobile/
├── pubspec.yaml            依存定義（docs/require.md 付録B 準拠）
├── analysis_options.yaml   Lint 設定
├── lib/
│   └── main.dart           エントリポイント
└── .env.example
```

## 補足

- API 通信は Go バックエンド（`backend/`）に対して `dio` で行う。
- 認証は `google_sign_in` で Google サインインし、トークンを Go バックエンドで検証する想定。
- 画面設計は `docs/design/screens.md` を参照。
