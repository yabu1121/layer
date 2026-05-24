import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/pin.dart';
import '../map/pin_repository.dart';

/// 指定ユーザーの投稿一覧（可視 Pin を著者で絞り込む）。
final userPinsProvider =
    FutureProvider.family<List<Pin>, String>((ref, userId) async {
  final all = await ref.read(pinRepositoryProvider).fetchVisible();
  return all.where((p) => p.author.id == userId).toList();
});

/// 友達など他ユーザーのプロフィール画面（issue: フレンドのプロフィール遷移）。
/// 表示する公開情報は遷移時に [PinAuthor] を extra で受け取る。
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.user});

  final PinAuthor user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pins = ref.watch(userPinsProvider(user.id));

    return Scaffold(
      appBar: AppBar(title: Text(user.displayName)),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Text(user.icon, style: const TextStyle(fontSize: 56)),
                const SizedBox(height: 8),
                Text(user.displayName, style: theme.textTheme.titleLarge),
                Text('@${user.userId}', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('投稿', style: theme.textTheme.titleSmall),
          ),
          pins.when(
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('まだ投稿はありません')),
                  )
                : Column(
                    children: [
                      for (final pin in list)
                        ListTile(
                          leading: const Icon(Icons.place),
                          title: Text(pin.body),
                          onTap: () => context.push('/pin/${pin.id}'),
                        ),
                    ],
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('投稿を取得できませんでした')),
            ),
          ),
        ],
      ),
    );
  }
}
