import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/api/api_client.dart';
import 'package:layer/features/onboarding/onboarding_controller.dart';

/// リクエストボディを捕捉し、固定ステータスを返す偽アダプタ。
class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter({this.statusCode = 200, this.body = '{}'});

  final int statusCode;
  final String body;
  Map<String, dynamic>? capturedBody;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (requestStream != null) {
      final bytes = await requestStream.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      capturedBody = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    }
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

ProviderContainer _container(_CapturingAdapter adapter) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('初期状態: アイコン選択済み・user_id は規約に合致・未入力で invalid', () {
    final c = _container(_CapturingAdapter());
    final state = c.read(onboardingControllerProvider);

    expect(state.icon, isNotEmpty);
    expect(RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(state.userId), isTrue);
    expect(state.displayName, '');
    expect(state.isValid, isFalse); // 名前未入力
  });

  test('バリデーション: 名前と user_id が妥当なら valid', () {
    final c = _container(_CapturingAdapter());
    final n = c.read(onboardingControllerProvider.notifier);

    n.updateDisplayName('リョウ');
    n.updateUserId('riyo_1234');
    expect(c.read(onboardingControllerProvider).isValid, isTrue);

    // 名前 21 文字 → invalid
    n.updateDisplayName('あ' * 21);
    expect(c.read(onboardingControllerProvider).isValid, isFalse);

    // user_id 不正（短すぎ / 記号）
    n.updateDisplayName('リョウ');
    n.updateUserId('ab');
    expect(c.read(onboardingControllerProvider).isValid, isFalse);
    n.updateUserId('bad id!');
    expect(c.read(onboardingControllerProvider).isValid, isFalse);
  });

  test('submit 成功: snake_case でPOSTし success', () async {
    final adapter = _CapturingAdapter(statusCode: 200, body: '{"user":{}}');
    final c = _container(adapter);
    final n = c.read(onboardingControllerProvider.notifier);
    n.updateDisplayName(' リョウ ');
    n.updateIcon('😎');
    n.updateUserId('riyo_1234');

    final result = await n.submit();

    expect(result, OnboardingSubmitResult.success);
    expect(adapter.calls, 1);
    expect(adapter.capturedBody, {
      'display_name': 'リョウ', // trim 済み
      'icon': '😎',
      'user_id': 'riyo_1234',
    });
  });

  test('submit 409: userIdTaken でフィールドエラーを立てる', () async {
    final adapter =
        _CapturingAdapter(statusCode: 409, body: '{"error":"user_id_taken"}');
    final c = _container(adapter);
    final n = c.read(onboardingControllerProvider.notifier);
    n.updateDisplayName('リョウ');
    n.updateUserId('taken_id');

    final result = await n.submit();

    expect(result, OnboardingSubmitResult.userIdTaken);
    expect(c.read(onboardingControllerProvider).userIdError, isNotNull);
    expect(c.read(onboardingControllerProvider).isSubmitting, isFalse);
  });

  test('submit その他エラー: networkError', () async {
    final adapter = _CapturingAdapter(statusCode: 500, body: '{}');
    final c = _container(adapter);
    final n = c.read(onboardingControllerProvider.notifier);
    n.updateDisplayName('リョウ');
    n.updateUserId('riyo_1234');

    final result = await n.submit();

    expect(result, OnboardingSubmitResult.networkError);
  });

  test('user_id を編集すると 409 エラーが消える', () async {
    final adapter =
        _CapturingAdapter(statusCode: 409, body: '{"error":"user_id_taken"}');
    final c = _container(adapter);
    final n = c.read(onboardingControllerProvider.notifier);
    n.updateDisplayName('リョウ');
    n.updateUserId('taken_id');
    await n.submit();
    expect(c.read(onboardingControllerProvider).userIdError, isNotNull);

    n.updateUserId('new_id_99');
    expect(c.read(onboardingControllerProvider).userIdError, isNull);
  });
}
