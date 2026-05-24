// プラットフォームに応じて Web 用 Google サインインボタンを提供する。
// Web では GIS ボタンを描画、それ以外は何も描かない（スタブ）。
export 'web_google_signin_stub.dart'
    if (dart.library.html) 'web_google_signin_web.dart';
