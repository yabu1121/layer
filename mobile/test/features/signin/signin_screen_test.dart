import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:layer/core/api/api_client.dart';
import 'package:layer/core/auth/auth_storage.dart';
import 'package:layer/core/auth/google_auth.dart';
import 'package:layer/features/signin/signin_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGoogleAuth implements GoogleAuthService {
  _FakeGoogleAuth({this.idToken});

  final String? idToken;

  @override
  Future<String?> signIn() async => idToken;

  @override
  Future<void> signOut() async {}
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.statusCode = 200});

  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString('{}', statusCode);
  }

  @override
  void close({bool force = false}) {}
}

Future<Widget> _app({
  required GoogleAuthService google,
  required _StubAdapter adapter,
  required AuthStorage storage,
}) async {
  final router = GoRouter(
    initialLocation: '/signin',
    routes: [
      GoRoute(path: '/signin', builder: (c, s) => const SignInScreen()),
      GoRoute(
        path: '/',
        builder: (c, s) => const Scaffold(body: Text('HOME_MARKER')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      googleAuthServiceProvider.overrideWithValue(google),
      authStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('成功 → / へ遷移する', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = AuthStorage(await SharedPreferences.getInstance());

    await tester.pumpWidget(
      await _app(
        google: _FakeGoogleAuth(idToken: 'gid'),
        adapter: _StubAdapter(statusCode: 200),
        storage: storage,
      ),
    );

    await tester.tap(find.text('Google でサインイン'));
    await tester.pumpAndSettle();

    expect(find.text('HOME_MARKER'), findsOneWidget);
    expect(storage.readIdToken(), 'gid');
  });

  testWidgets('401 → スナックバーを表示する（無遷移）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = AuthStorage(await SharedPreferences.getInstance());

    await tester.pumpWidget(
      await _app(
        google: _FakeGoogleAuth(idToken: 'gid'),
        adapter: _StubAdapter(statusCode: 401),
        storage: storage,
      ),
    );

    await tester.tap(find.text('Google でサインイン'));
    await tester.pump(); // タップ処理
    await tester.pump(); // 非同期完了 → AsyncError
    await tester.pump(const Duration(milliseconds: 750)); // スナックバー表示

    expect(find.text('サインインに失敗しました。もう一度お試しください'), findsOneWidget);
    expect(find.text('HOME_MARKER'), findsNothing);
    expect(storage.readIdToken(), isNull);
  });
}
