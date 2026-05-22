import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google サインインの抽象。`google_sign_in` を直接参照せずテストで差し替える
/// ためのインターフェース。
abstract class GoogleAuthService {
  /// サインインして ID トークンを返す。ユーザーがキャンセルした場合は null。
  Future<String?> signIn();

  /// サインアウトする（ProfileScreen 等で使用）。
  Future<void> signOut();
}

/// `google_sign_in` を用いた本番実装。
class GoogleSignInService implements GoogleAuthService {
  GoogleSignInService([GoogleSignIn? googleSignIn])
      : _google = googleSignIn ?? GoogleSignIn();

  final GoogleSignIn _google;

  @override
  Future<String?> signIn() async {
    final account = await _google.signIn();
    if (account == null) return null; // キャンセル
    final idToken = (await account.authentication).idToken;
    if (idToken == null) {
      throw StateError('Google ID トークンを取得できませんでした');
    }
    return idToken;
  }

  @override
  Future<void> signOut() => _google.signOut();
}

/// [GoogleAuthService] の Provider。
final googleAuthServiceProvider = Provider<GoogleAuthService>(
  (ref) => GoogleSignInService(),
);
