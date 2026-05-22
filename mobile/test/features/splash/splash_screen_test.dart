import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:layer/core/api/api_client.dart';
import 'package:layer/core/auth/auth_storage.dart';
import 'package:layer/features/splash/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.throwError = false});

  final bool throwError;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (throwError) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

Future<Widget> _app({
  required AuthStorage storage,
  required _StubAdapter adapter,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (c, s) => const SplashScreen()),
      GoRoute(
        path: '/signin',
        builder: (c, s) => const Scaffold(body: Text('SIGNIN_PAGE')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      authStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('トークン無し → /signin へ遷移する', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = AuthStorage(prefs);

    await tester.pumpWidget(
      await _app(storage: storage, adapter: _StubAdapter()),
    );
    await tester.pumpAndSettle();

    expect(find.text('SIGNIN_PAGE'), findsOneWidget);
  });

  testWidgets('ネットワークエラー時は再試行ボタンを表示する', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = AuthStorage(prefs);
    await storage.saveIdToken('tok');

    await tester.pumpWidget(
      await _app(storage: storage, adapter: _StubAdapter(throwError: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('再試行'), findsOneWidget);
  });
}
