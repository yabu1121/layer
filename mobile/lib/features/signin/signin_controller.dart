import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_storage.dart';
import '../../core/auth/google_auth.dart';

/// SignInScreen のコントローラ（issue #31）。
///
/// Google サインインで ID トークンを取得し、`POST /api/auth/sign-in` で検証・
/// ユーザー upsert を行い、成功すれば id_token を保存する。
///
/// 初期状態を `AsyncData` にするため [Notifier]`<AsyncValue<void>>` を使う
/// （`AsyncNotifier` は初期化中 `AsyncLoading` になりボタンが押せなくなるため）。
class SignInController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Google サインインを実行する。
  ///
  /// - 成功: id_token を保存し true を返す（呼び出し側で `/` へ遷移）。
  /// - キャンセル: 何もせず false（state は data のまま、無遷移）。
  /// - 失敗: state を [AsyncError] にして false（UI がスナックバー表示）。
  Future<bool> signInWithGoogle() async {
    state = const AsyncLoading();
    try {
      final idToken = await ref.read(googleAuthServiceProvider).signIn();
      if (idToken == null) {
        state = const AsyncData(null); // キャンセル
        return false;
      }
      await ref.read(apiClientProvider).post<dynamic>(
        '/api/auth/sign-in',
        data: {'id_token': idToken},
      );
      // 検証成功後に保存する（Bearer に自動付与される）。
      await ref.read(authStorageProvider).saveIdToken(idToken);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError<void>(e, st);
      return false;
    }
  }

  /// 取得済みの ID トークンでバックエンドにサインインする（Web の GIS 用）。
  Future<bool> signInWithIdToken(String idToken) async {
    state = const AsyncLoading();
    try {
      await ref.read(apiClientProvider).post<dynamic>(
        '/api/auth/sign-in',
        data: {'id_token': idToken},
      );
      await ref.read(authStorageProvider).saveIdToken(idToken);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError<void>(e, st);
      return false;
    }
  }

  /// 開発専用サインイン。Google を介さず固定 id_token でバックエンドに入る。
  /// バックエンドの DEV_AUTH_BYPASS が有効なときのみ通る。画面側で
  /// kDebugMode のときだけ呼ぶこと。
  Future<bool> signInDev() async {
    state = const AsyncLoading();
    try {
      const devToken = 'dev-user';
      await ref.read(apiClientProvider).post<dynamic>(
        '/api/auth/sign-in',
        data: {'id_token': devToken},
      );
      await ref.read(authStorageProvider).saveIdToken(devToken);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError<void>(e, st);
      return false;
    }
  }
}

final signInControllerProvider =
    NotifierProvider<SignInController, AsyncValue<void>>(SignInController.new);
