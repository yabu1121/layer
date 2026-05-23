import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_notification.dart';
import 'notification_repository.dart';

/// 起動時バナーで表示する 1 件を選ぶコントローラ（issue #44）。
///
/// 未読のうち discovery > friend_request > reaction の優先で 1 件を出す。
/// 一度閉じた通知はセッション中（このコントローラ生存中）再表示しない。
class NotificationBannerController extends Notifier<AppNotification?> {
  static const _priority = ['discovery', 'friend_request', 'reaction'];

  final Set<String> _dismissed = {};

  @override
  AppNotification? build() => null;

  Future<void> load() async {
    try {
      final items = await ref.read(notificationRepositoryProvider).list();
      final unread = items
          .where((n) => n.isUnread && !_dismissed.contains(n.id))
          .toList();
      state = _pick(unread);
    } catch (_) {
      // 取得失敗時はバナーを変えない。
    }
  }

  AppNotification? _pick(List<AppNotification> unread) {
    for (final kind in _priority) {
      for (final n in unread) {
        if (n.kind == kind) return n;
      }
    }
    return null;
  }

  /// バナーを閉じる。以降このセッションでは同じ通知を出さない。
  void dismiss(AppNotification notification) {
    _dismissed.add(notification.id);
    state = null;
  }
}

final notificationBannerProvider =
    NotifierProvider<NotificationBannerController, AppNotification?>(
  NotificationBannerController.new,
);
