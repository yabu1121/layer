import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/features/notifications/app_notification.dart';
import 'package:layer/features/notifications/notification_banner_controller.dart';
import 'package:layer/features/notifications/notification_repository.dart';

AppNotification _n(String id, String kind, {bool read = false}) =>
    AppNotification(
      id: id,
      kind: kind,
      payload: const {'displayName': 'アヤ', 'icon': '🌸'},
      readAt: read ? DateTime(2026) : null,
      createdAt: DateTime(2026),
    );

class _FakeRepo implements NotificationRepository {
  _FakeRepo(this.items);
  List<AppNotification> items;
  @override
  Future<List<AppNotification>> list({int limit = 50}) async => items;
  @override
  Future<void> markAllRead() async {}
  @override
  Future<int> fetchUnreadCount() async => 0;
}

ProviderContainer _container(_FakeRepo repo) {
  final c = ProviderContainer(
    overrides: [notificationRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('優先度 discovery > friend_request > reaction', () async {
    final c = _container(_FakeRepo([
      _n('r', 'reaction'),
      _n('fr', 'friend_request'),
      _n('d', 'discovery'),
    ]));
    await c.read(notificationBannerProvider.notifier).load();
    expect(c.read(notificationBannerProvider)!.id, 'd');
  });

  test('discovery が無ければ friend_request', () async {
    final c = _container(_FakeRepo([_n('r', 'reaction'), _n('fr', 'friend_request')]));
    await c.read(notificationBannerProvider.notifier).load();
    expect(c.read(notificationBannerProvider)!.kind, 'friend_request');
  });

  test('既読は対象外、未読 0 で null', () async {
    final c = _container(_FakeRepo([_n('d', 'discovery', read: true)]));
    await c.read(notificationBannerProvider.notifier).load();
    expect(c.read(notificationBannerProvider), isNull);
  });

  test('閉じたら以降の load でも出ない', () async {
    final repo = _FakeRepo([_n('d', 'discovery')]);
    final c = _container(repo);
    final n = c.read(notificationBannerProvider.notifier);
    await n.load();
    final banner = c.read(notificationBannerProvider)!;

    n.dismiss(banner);
    expect(c.read(notificationBannerProvider), isNull);

    await n.load(); // 再取得しても抑制される
    expect(c.read(notificationBannerProvider), isNull);
  });
}
