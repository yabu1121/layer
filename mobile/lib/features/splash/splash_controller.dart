import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_storage.dart';
import '../../core/models/user.dart';

/// Splash 後の遷移先（screens.md §3.1 起動〜認証フロー）。
enum SplashDestination { signIn, onboarding, map }

/// 起動時の振り分け判定（issue #30）。
///
/// 1. id_token 無し → signIn
/// 2. id_token 有り → GET /api/me
///    - 401 → トークン破棄 → signIn
///    - 200 + displayName 空 → onboarding / 入っていれば → map
/// 3. ネットワークエラー等は rethrow し、UI（再試行ボタン）に委ねる。
///
/// autoDispose にして、SplashScreen を再表示するたびに再評価させる
/// （サインイン後に `/` へ戻った際、キャッシュ値のままで止まらないように）。
final splashDestinationProvider =
    FutureProvider.autoDispose<SplashDestination>((ref) async {
  final authStorage = ref.watch(authStorageProvider);
  final token = authStorage.readIdToken();
  if (token == null || token.isEmpty) {
    return SplashDestination.signIn;
  }

  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get<Map<String, dynamic>>('/api/me');
    final user = User.fromJson(
      (res.data!['user'] as Map).cast<String, dynamic>(),
    );
    return user.hasProfile ? SplashDestination.map : SplashDestination.onboarding;
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) {
      await authStorage.clear();
      return SplashDestination.signIn;
    }
    rethrow;
  }
});
