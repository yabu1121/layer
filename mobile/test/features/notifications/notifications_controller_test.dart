import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/models/pin.dart';
import 'package:layer/features/friends/friend_repository.dart';
import 'package:layer/features/notifications/app_notification.dart';
import 'package:layer/features/notifications/notification_repository.dart';
import 'package:layer/features/notifications/notifications_controller.dart';

AppNotification _notif(String id, String kind, {String? requestId}) =>
    AppNotification(
      id: id,
      kind: kind,
      payload: {
        'displayName': 'アヤ',
        'icon': '🌸',
        if (requestId != null) 'requestId': requestId,
      },
      createdAt: DateTime(2026, 1, 1),
    );

class _FakeNotifRepo implements NotificationRepository {
  _FakeNotifRepo(this.items);
  final List<AppNotification> items;
  int markAllReadCalls = 0;

  @override
  Future<List<AppNotification>> list({int limit = 50}) async => items;
  @override
  Future<void> markAllRead() async => markAllReadCalls++;
  @override
  Future<int> fetchUnreadCount() async => 0;
}

class _FakeFriendRepo implements FriendRepository {
  String? acceptedId;
  String? rejectedId;

  @override
  Future<void> accept(String requestId) async => acceptedId = requestId;
  @override
  Future<void> reject(String requestId) async => rejectedId = requestId;
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

ProviderContainer _container(_FakeNotifRepo repo, {_FakeFriendRepo? friend}) {
  final c = ProviderContainer(
    overrides: [
      notificationRepositoryProvider.overrideWithValue(repo),
      friendRepositoryProvider.overrideWithValue(friend ?? _FakeFriendRepo()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('load: 一覧取得し、既読化する', () async {
    final repo = _FakeNotifRepo([_notif('n1', 'discovery')]);
    final c = _container(repo);
    await c.read(notificationsControllerProvider.notifier).load();
    final s = c.read(notificationsControllerProvider);
    expect(s.status, NotificationsStatus.ready);
    expect(s.items.length, 1);
    expect(repo.markAllReadCalls, 1);
  });

  test('load: 0 件でも ready', () async {
    final c = _container(_FakeNotifRepo(const []));
    await c.read(notificationsControllerProvider.notifier).load();
    expect(c.read(notificationsControllerProvider).items, isEmpty);
    expect(
      c.read(notificationsControllerProvider).status,
      NotificationsStatus.ready,
    );
  });

  test('acceptRequest: friend API を叩いて一覧から除去', () async {
    final friend = _FakeFriendRepo();
    final repo = _FakeNotifRepo([_notif('n1', 'friend_request', requestId: 'r1')]);
    final c = _container(repo, friend: friend);
    final n = c.read(notificationsControllerProvider.notifier);
    await n.load();

    final ok = await n.acceptRequest(_notif('n1', 'friend_request', requestId: 'r1'));
    expect(ok, isTrue);
    expect(friend.acceptedId, 'r1');
    expect(c.read(notificationsControllerProvider).items, isEmpty);
  });

  test('rejectRequest: friend API を叩いて一覧から除去', () async {
    final friend = _FakeFriendRepo();
    final repo = _FakeNotifRepo([_notif('n1', 'friend_request', requestId: 'r1')]);
    final c = _container(repo, friend: friend);
    final n = c.read(notificationsControllerProvider.notifier);
    await n.load();

    await n.rejectRequest(_notif('n1', 'friend_request', requestId: 'r1'));
    expect(friend.rejectedId, 'r1');
    expect(c.read(notificationsControllerProvider).items, isEmpty);
  });
}
