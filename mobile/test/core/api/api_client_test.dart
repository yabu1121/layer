import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/api/api_client.dart';
import 'package:layer/core/auth/auth_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 送信直前の RequestOptions を捕捉する偽アダプタ。実際の通信は行わない。
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? captured;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured = options;
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<AuthStorage> _newStorage() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return AuthStorage(prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('baseUrl を設定する', () async {
    final dio = createApiClient(
      baseUrl: 'http://example.test',
      authStorage: await _newStorage(),
    );
    expect(dio.options.baseUrl, 'http://example.test');
  });

  test('保存済み ID トークンを Bearer として付与する', () async {
    final storage = await _newStorage();
    await storage.saveIdToken('token-xyz');

    final dio = createApiClient(
      baseUrl: 'http://example.test',
      authStorage: storage,
    );
    final adapter = _CapturingAdapter();
    dio.httpClientAdapter = adapter;

    await dio.get<dynamic>('/api/me');

    expect(adapter.captured!.headers['Authorization'], 'Bearer token-xyz');
  });

  test('トークン未保存なら Authorization を付けない', () async {
    final storage = await _newStorage();

    final dio = createApiClient(
      baseUrl: 'http://example.test',
      authStorage: storage,
    );
    final adapter = _CapturingAdapter();
    dio.httpClientAdapter = adapter;

    await dio.get<dynamic>('/health');

    expect(adapter.captured!.headers.containsKey('Authorization'), isFalse);
  });
}
