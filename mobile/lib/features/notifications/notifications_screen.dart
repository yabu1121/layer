import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_notification.dart';
import 'notifications_controller.dart';

/// お知らせ一覧（screens.md §2.7 / issue #43）。発見通知を最も目立たせる。
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsControllerProvider.notifier).load();
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _accept(AppNotification n) async {
    final ok =
        await ref.read(notificationsControllerProvider.notifier).acceptRequest(n);
    if (mounted) _snack(ok ? '友達になりました' : '承認に失敗しました');
  }

  Future<void> _reject(AppNotification n) async {
    final ok =
        await ref.read(notificationsControllerProvider.notifier).rejectRequest(n);
    if (!ok && mounted) _snack('拒否に失敗しました');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('お知らせ')),
      body: switch (state.status) {
        NotificationsStatus.loading =>
          const Center(child: CircularProgressIndicator()),
        NotificationsStatus.error => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('読み込みに失敗しました'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      ref.read(notificationsControllerProvider.notifier).load(),
                  child: const Text('再試行'),
                ),
              ],
            ),
          ),
        NotificationsStatus.ready => state.items.isEmpty
            ? const Center(child: Text('まだお知らせはありません'))
            : ListView.separated(
                itemCount: state.items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _NotificationTile(
                  notification: state.items[i],
                  onAccept: () => _accept(state.items[i]),
                  onReject: () => _reject(state.items[i]),
                ),
              ),
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onAccept,
    required this.onReject,
  });

  final AppNotification notification;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final theme = Theme.of(context);
    final isDiscovery = n.kind == 'discovery';

    return Container(
      // 発見通知だけ強調カラー。
      color: isDiscovery ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        leading: Text(_kindEmoji(n.kind), style: const TextStyle(fontSize: 22)),
        title: Text(_title(n)),
        subtitle: Text(_timeAgo(n.createdAt)),
        trailing: n.kind == 'friend_request'
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(onPressed: onAccept, child: const Text('承認')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: onReject, child: const Text('拒否')),
                ],
              )
            : null,
        onTap: (n.kind == 'discovery' || n.kind == 'reaction') &&
                n.pinId != null
            ? () => context.push('/pin/${n.pinId}')
            : null,
      ),
    );
  }
}

String _kindEmoji(String kind) => switch (kind) {
      'discovery' => '🎯',
      'reaction' => '💛',
      'friend_request' => '👋',
      'friend_accepted' => '✅',
      _ => '🔔',
    };

String _title(AppNotification n) {
  final name = n.displayName;
  return switch (n.kind) {
    'discovery' => '$name があなたと同じ場所に Pin を立てました',
    'reaction' => '$name があなたの Pin に「わかる」を押しました',
    'friend_request' => '$name から友達申請が届きました',
    'friend_accepted' => '$name があなたの申請を承認しました',
    _ => 'お知らせ',
  };
}

/// 24 時間以内は相対表示、それ以降は M/D。
String _timeAgo(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'たった今';
  if (diff.inHours < 1) return '${diff.inMinutes}分前';
  if (diff.inHours < 24) return '${diff.inHours}時間前';
  return '${time.month}/${time.day}';
}
