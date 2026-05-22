import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:layer/core/api/api_client.dart';
import 'package:layer/features/onboarding/onboarding_screen.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.statusCode = 200, this.body = '{}'});

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
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

Widget _app(_StubAdapter adapter) {
  final router = GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingScreen()),
      GoRoute(
        path: '/map',
        builder: (c, s) => const Scaffold(body: Text('MAP_MARKER')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('「はじめる」は名前未入力なら無効、入力で有効になる', (tester) async {
    await tester.pumpWidget(_app(_StubAdapter()));
    await tester.pumpAndSettle();

    FilledButton button() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'はじめる'),
        );
    expect(button().onPressed, isNull); // 名前未入力

    await tester.enterText(find.widgetWithText(TextField, '名前').first, 'リョウ');
    await tester.pump();
    expect(button().onPressed, isNotNull); // user_id はプリフィル済み
  });

  testWidgets('成功 → /map へ遷移する', (tester) async {
    await tester.pumpWidget(_app(_StubAdapter(statusCode: 200, body: '{"user":{}}')));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '名前').first, 'リョウ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'はじめる'));
    await tester.pumpAndSettle();

    expect(find.text('MAP_MARKER'), findsOneWidget);
  });

  testWidgets('409 → user_id エラーを表示し遷移しない', (tester) async {
    await tester.pumpWidget(
      _app(_StubAdapter(statusCode: 409, body: '{"error":"user_id_taken"}')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '名前').first, 'リョウ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'はじめる'));
    await tester.pumpAndSettle();

    expect(find.text('このユーザーIDは既に使われています'), findsOneWidget);
    expect(find.text('MAP_MARKER'), findsNothing);
  });
}
