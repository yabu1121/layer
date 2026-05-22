import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/api/api_client.dart';
import 'package:layer/core/auth/auth_storage.dart';
import 'package:layer/core/auth/google_auth.dart';
import 'package:layer/features/signin/signin_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGoogleAuth implements GoogleAuthService {
  _FakeGoogleAuth({this.idToken, this.error});

  final String? idToken; // null = キャンセル
  final Object? error;
  int signInCalls = 0;

  @override
  Future<String?> signIn() async {
    signInCalls++;
    if (error != null) throw error!;
    return idToken;
  }

  @override
  Future<void> signOut() async {}
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.statusCode = 200, this.body = '{}'});

  final int statusCode;
  final String body;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<AuthStorage> _storage() async {
  SharedPreferences.setMockInitialValues({});
  return AuthStorage(await SharedPreferences.getInstance());
}

ProviderContainer _container({
  required GoogleAuthService google,
  required AuthStorage storage,
  required _StubAdapter adapter,
}) {
  final container = ProviderContainer(
    overrides: [
      googleAuthServiceProvider.overrideWithValue(google),
      authStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('成功: /api/auth/sign-in を叩き id_token を保存して true', () async {
    final google = _FakeGoogleAuth(idToken: 'gid-123');
    final storage = await _storage();
    final adapter = _StubAdapter(
      statusCode: 200,
      body: '{"user":{"id":"u1"},"is_new":true}',
    );
    final c = _container(google: google, storage: storage, adapter: adapter);

    final ok =
        await c.read(signInControllerProvider.notifier).signInWithGoogle();

    expect(ok, isTrue);
    expect(adapter.calls, 1);
    expect(storage.readIdToken(), 'gid-123');
    expect(c.read(signInControllerProvider), isA<AsyncData<void>>());
  });

  test('キャンセル: 何もせず false、API もトークン保存も無し', () async {
    final google = _FakeGoogleAuth(idToken: null);
    final storage = await _storage();
    final adapter = _StubAdapter();
    final c = _container(google: google, storage: storage, adapter: adapter);

    final ok =
        await c.read(signInControllerProvider.notifier).signInWithGoogle();

    expect(ok, isFalse);
    expect(adapter.calls, 0);
    expect(storage.readIdToken(), isNull);
    expect(c.read(signInControllerProvider), isA<AsyncData<void>>());
  });

  test('401: AsyncError、トークン保存しない', () async {
    final google = _FakeGoogleAuth(idToken: 'gid-123');
    final storage = await _storage();
    final adapter = _StubAdapter(statusCode: 401, body: '{"message":"invalid"}');
    final c = _container(google: google, storage: storage, adapter: adapter);

    final ok =
        await c.read(signInControllerProvider.notifier).signInWithGoogle();

    expect(ok, isFalse);
    expect(storage.readIdToken(), isNull);
    expect(c.read(signInControllerProvider), isA<AsyncError<void>>());
  });

  test('Google 側の例外: AsyncError、API は叩かない', () async {
    final google = _FakeGoogleAuth(error: StateError('boom'));
    final storage = await _storage();
    final adapter = _StubAdapter();
    final c = _container(google: google, storage: storage, adapter: adapter);

    final ok =
        await c.read(signInControllerProvider.notifier).signInWithGoogle();

    expect(ok, isFalse);
    expect(adapter.calls, 0);
    expect(c.read(signInControllerProvider), isA<AsyncError<void>>());
  });
}
