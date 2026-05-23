import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/models/pin.dart';
import 'package:layer/features/friends/friend_repository.dart';
import 'package:layer/features/notifications/app_notification.dart';
import 'package:layer/features/notifications/notification_repository.dart';
import 'package:layer/features/notifications/notifications_screen.dart';

AppNotification _notif(String id, String kind) => AppNotification(
      id: id,
      kind: kind,
      payload: const {'displayName': 'アヤ', 'icon': '🌸', 'requestId': 'r1'},
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    );

class _FakeNotifRepo implements NotificationRepository {
  _FakeNotifRepo(this.items);
  final List<AppNotification> items;
  @override
  Future<List<AppNotification>> list({int limit = 50}) async => items;
  @override
  Future<void> markAllRead() async {}
  @override
  Future<int> fetchUnreadCount() async => 0;
}

class _FakeFriendRepo implements FriendRepository {
  @override
  Future<void> accept(String requestId) async {}
  @override
  Future<void> reject(String requestId) async {}
  @override
  Future<PinAuthor?> searchUser(String userId) async => null;
  @override
  Future<List<PinAuthor>> listFriends() async => const [];
  @override
  Future<SendRequestResult> sendRequest(String receiverId) async =>
      SendRequestResult.sent;
  @override
  Future<List<IncomingRequest>> listIncoming() async => const [];
}

Widget _app(List<AppNotification> items) => ProviderScope(
      overrides: [
        notificationRepositoryProvider.overrideWithValue(_FakeNotifRepo(items)),
        friendRepositoryProvider.overrideWithValue(_FakeFriendRepo()),
      ],
      child: const MaterialApp(home: NotificationsScreen()),
    );

void main() {
  testWidgets('種別ごとに表示、friend_request はインライン操作', (tester) async {
    await tester.pumpWidget(_app([
      _notif('n1', 'discovery'),
      _notif('n2', 'friend_request'),
    ]));
    await tester.pumpAndSettle();

    expect(find.textContaining('同じ場所に Pin を立てました'), findsOneWidget);
    expect(find.textContaining('友達申請が届きました'), findsOneWidget);
    expect(find.text('承認'), findsOneWidget);
    expect(find.text('拒否'), findsOneWidget);
  });

  testWidgets('0 件で空状態メッセージ', (tester) async {
    await tester.pumpWidget(_app(const []));
    await tester.pumpAndSettle();
    expect(find.text('まだお知らせはありません'), findsOneWidget);
  });
}
