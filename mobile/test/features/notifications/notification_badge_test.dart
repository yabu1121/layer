import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/features/notifications/notification_badge_controller.dart';
import 'package:layer/features/notifications/notification_repository.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository(this.count);

  int count;
  bool throwError = false;

  @override
  Future<int> fetchUnreadCount() async {
    if (throwError) throw Exception('network');
    return count;
  }
}

void main() {
  test('repository: unread-count をパースする', () async {
    final dio = Dio()..httpClientAdapter = _StubAdapter('{"count":3}');
    final repo = ApiNotificationRepository(dio);
    expect(await repo.fetchUnreadCount(), 3);
  });

  test('repository: count 欠落は 0', () async {
    final dio = Dio()..httpClientAdapter = _StubAdapter('{}');
    expect(await ApiNotificationRepository(dio).fetchUnreadCount(), 0);
  });

  test('badge: refresh で未読数を更新する', () async {
    final c = ProviderContainer(
      overrides: [
        notificationRepositoryProvider
            .overrideWithValue(_FakeNotificationRepository(5)),
      ],
    );
    addTearDown(c.dispose);

    expect(c.read(notificationBadgeProvider), 0);
    await c.read(notificationBadgeProvider.notifier).refresh();
    expect(c.read(notificationBadgeProvider), 5);
  });

  test('badge: 取得失敗時は前回値を維持する', () async {
    final repo = _FakeNotificationRepository(5);
    final c = ProviderContainer(
      overrides: [notificationRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);

    await c.read(notificationBadgeProvider.notifier).refresh();
    expect(c.read(notificationBadgeProvider), 5);

    repo
      ..throwError = true
      ..count = 9;
    await c.read(notificationBadgeProvider.notifier).refresh();
    expect(c.read(notificationBadgeProvider), 5); // 維持
  });
}
