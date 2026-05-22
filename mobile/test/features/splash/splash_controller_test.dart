import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/api/api_client.dart';
import 'package:layer/core/auth/auth_storage.dart';
import 'package:layer/features/splash/splash_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 固定レスポンスを返す、または例外を投げる偽アダプタ。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.statusCode, this.body, this.throwError = false});

  final int? statusCode;
  final String? body;
  final bool throwError;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (throwError) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'network down',
      );
    }
    return ResponseBody.fromString(
      body ?? '{}',
      statusCode ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<AuthStorage> _storage({String? token}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = AuthStorage(prefs);
  if (token != null) await storage.saveIdToken(token);
  return storage;
}

ProviderContainer _container(AuthStorage storage, _StubAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  final container = ProviderContainer(
    overrides: [
      authStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(dio),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('トークン無し → signIn（/api/me は叩かない）', () async {
    final adapter = _StubAdapter();
    final container = _container(await _storage(), adapter);

    final dest = await container.read(splashDestinationProvider.future);

    expect(dest, SplashDestination.signIn);
    expect(adapter.calls, 0);
  });

  test('トークン有 + displayName 空 → onboarding', () async {
    final adapter = _StubAdapter(
      statusCode: 200,
      body: '{"user":{"id":"u1","userId":"user_x","displayName":"","icon":""}}',
    );
    final container = _container(await _storage(token: 'tok'), adapter);

    final dest = await container.read(splashDestinationProvider.future);

    expect(dest, SplashDestination.onboarding);
  });

  test('トークン有 + displayName 有 → map', () async {
    final adapter = _StubAdapter(
      statusCode: 200,
      body:
          '{"user":{"id":"u1","userId":"user_x","displayName":"たろう","icon":"🐱"}}',
    );
    final container = _container(await _storage(token: 'tok'), adapter);

    final dest = await container.read(splashDestinationProvider.future);

    expect(dest, SplashDestination.map);
  });

  test('401 → トークンを破棄して signIn', () async {
    final adapter = _StubAdapter(statusCode: 401, body: '{"message":"invalid"}');
    final storage = await _storage(token: 'expired');
    final container = _container(storage, adapter);

    final dest = await container.read(splashDestinationProvider.future);

    expect(dest, SplashDestination.signIn);
    expect(storage.readIdToken(), isNull);
  });

  test('ネットワークエラー → error 状態（再試行用に rethrow）', () async {
    final adapter = _StubAdapter(throwError: true);
    final container = _container(await _storage(token: 'tok'), adapter);

    await expectLater(
      container.read(splashDestinationProvider.future),
      throwsA(isA<DioException>()),
    );
  });
}
