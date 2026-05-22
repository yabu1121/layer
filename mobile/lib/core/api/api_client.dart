import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_storage.dart';

/// Go バックエンド REST API を叩く dio クライアントを構築する。
///
/// baseUrl は `.env` の `API_BASE_URL`、各リクエストには保存済みの ID トークンを
/// `Authorization: Bearer <id_token>` として自動付与する。トークン未保存時は
/// ヘッダを付けない（サインイン前のリクエスト用）。
Dio createApiClient({
  required String baseUrl,
  required AuthStorage authStorage,
}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = authStorage.readIdToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ),
  );
  return dio;
}

/// API クライアント（dio）の Provider。
final apiClientProvider = Provider<Dio>((ref) {
  final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:8080';
  return createApiClient(
    baseUrl: baseUrl,
    authStorage: ref.watch(authStorageProvider),
  );
});
