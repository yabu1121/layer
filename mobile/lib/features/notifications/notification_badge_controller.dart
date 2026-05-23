import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_repository.dart';

/// 通知バッジの未読数（issue #35）。
///
/// 取得タイミング（30 秒ポーリング・画面再表示）は画面側が [refresh] を呼ぶ。
/// 取得失敗時は現状維持（バッジをちらつかせない）。
class NotificationBadgeController extends Notifier<int> {
  @override
  int build() => 0;

  Future<void> refresh() async {
    try {
      state = await ref.read(notificationRepositoryProvider).fetchUnreadCount();
    } catch (_) {
      // ネットワークエラー時は前回値を維持。
    }
  }
}

final notificationBadgeProvider =
    NotifierProvider<NotificationBadgeController, int>(
  NotificationBadgeController.new,
);
