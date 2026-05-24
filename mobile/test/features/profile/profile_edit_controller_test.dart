import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/api/api_client.dart';
import 'package:layer/core/models/user.dart';
import 'package:layer/features/profile/profile_edit_controller.dart';

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

const _user = User(
  id: 'me-id',
  userId: 'riyo_1234',
  displayName: 'リョウ',
  icon: '😎',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load: 既存プロフィールでフォームを初期化する', () {
    final c = _container(_CapturingAdapter());
    c.read(profileEditControllerProvider.notifier).load(_user);
    final s = c.read(profileEditControllerProvider);
    expect(s.displayName, 'リョウ');
    expect(s.icon, '😎');
    expect(s.userId, 'riyo_1234');
    expect(s.loaded, isTrue);
    expect(s.isValid, isTrue);
  });

  test('バリデーション: 名前を空にすると invalid', () {
    final c = _container(_CapturingAdapter());
    final n = c.read(profileEditControllerProvider.notifier)..load(_user);
    n.updateDisplayName('');
    expect(c.read(profileEditControllerProvider).isValid, isFalse);
  });

  test('submit: 成功で success・snake_case で送る', () async {
    final adapter = _CapturingAdapter(statusCode: 200, body: '{}');
    final c = _container(adapter);
    final n = c.read(profileEditControllerProvider.notifier)..load(_user);
    n.updateDisplayName('リョウ改');

    final result = await n.submit();
    expect(result, ProfileEditResult.success);
    expect(adapter.calls, 1);
    expect(adapter.capturedBody?['display_name'], 'リョウ改');
    expect(adapter.capturedBody?['user_id'], 'riyo_1234');
    expect(adapter.capturedBody?['icon'], '😎');
    expect(c.read(profileEditControllerProvider).isSubmitting, isFalse);
  });

  test('submit: 409 で userIdTaken とエラー表示', () async {
    final adapter = _CapturingAdapter(statusCode: 409, body: '{"error":"user_id_taken"}');
    final c = _container(adapter);
    final n = c.read(profileEditControllerProvider.notifier)..load(_user);

    final result = await n.submit();
    expect(result, ProfileEditResult.userIdTaken);
    expect(c.read(profileEditControllerProvider).userIdErrorText, isNotNull);
  });

  test('submit: 無効な入力は送信しない', () async {
    final adapter = _CapturingAdapter();
    final c = _container(adapter);
    final n = c.read(profileEditControllerProvider.notifier)..load(_user);
    n.updateDisplayName(''); // invalid

    final result = await n.submit();
    expect(result, ProfileEditResult.invalid);
    expect(adapter.calls, 0);
  });
}
