import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 認証トークン（Google サインインで得た ID トークン）の永続化を担う。
///
/// Go バックエンドは `Authorization: Bearer <id_token>` をそのまま検証する方式
/// （`backend/internal/middleware/auth.go`）のため、ここで保持するのは
/// Google の ID トークンそのもの。サインアウト時は [clear] で破棄する。
class AuthStorage {
  AuthStorage(this._prefs);

  static const _idTokenKey = 'id_token';

  final SharedPreferences _prefs;

  /// 保存済みの ID トークンを返す（未保存なら null）。
  String? readIdToken() => _prefs.getString(_idTokenKey);

  /// ID トークンを保存する。
  Future<void> saveIdToken(String token) =>
      _prefs.setString(_idTokenKey, token);

  /// ID トークンを削除する（サインアウト時）。
  Future<void> clear() => _prefs.remove(_idTokenKey);
}

/// SharedPreferences のインスタンスを供給する。
///
/// 非同期初期化のため `main()` で実体を `overrideWithValue` する。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider は main() で override してください',
  ),
);

/// [AuthStorage] の Provider。
final authStorageProvider = Provider<AuthStorage>(
  (ref) => AuthStorage(ref.watch(sharedPreferencesProvider)),
);
