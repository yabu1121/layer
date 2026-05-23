import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../friends/friend_repository.dart';
import 'app_notification.dart';
import 'notification_badge_controller.dart';
import 'notification_repository.dart';

enum NotificationsStatus { loading, ready, error }

class NotificationsState {
  const NotificationsState({
    this.status = NotificationsStatus.loading,
    this.items = const [],
  });

  final NotificationsStatus status;
  final List<AppNotification> items;

  NotificationsState copyWith({
    NotificationsStatus? status,
    List<AppNotification>? items,
  }) =>
      NotificationsState(
        status: status ?? this.status,
        items: items ?? this.items,
      );
}

/// NotificationsScreen のコントローラ（issue #43）。
class NotificationsController extends Notifier<NotificationsState> {
  @override
  NotificationsState build() => const NotificationsState();

  /// 一覧取得 → 既読化 → バッジを 0 に。
  Future<void> load() async {
    state = const NotificationsState();
    try {
      final repo = ref.read(notificationRepositoryProvider);
      final items = await repo.list();
      state = NotificationsState(
        status: NotificationsStatus.ready,
        items: items,
      );
      // 表示できたら既読化し、バッジを更新する（ベストエフォート）。
      try {
        await repo.markAllRead();
        await ref.read(notificationBadgeProvider.notifier).refresh();
      } catch (_) {}
    } catch (_) {
      state = const NotificationsState(status: NotificationsStatus.error);
    }
  }

  Future<bool> acceptRequest(AppNotification n) async {
    final id = n.requestId;
    if (id == null) return false;
    try {
      await ref.read(friendRepositoryProvider).accept(id);
      _remove(n);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> rejectRequest(AppNotification n) async {
    final id = n.requestId;
    if (id == null) return false;
    try {
      await ref.read(friendRepositoryProvider).reject(id);
      _remove(n);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _remove(AppNotification n) {
    state = state.copyWith(
      items: state.items.where((i) => i.id != n.id).toList(),
    );
  }
}

final notificationsControllerProvider =
    NotifierProvider<NotificationsController, NotificationsState>(
  NotificationsController.new,
);
