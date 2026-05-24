import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/models/pin.dart';
import '../../core/widgets/empty_view.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/loading_view.dart';
import '../map/pin_repository.dart';
import 'profile_header.dart';

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
            child: ProfileHeader(
              icon: user.icon,
              displayName: user.displayName,
              userId: user.userId,
              postCount: pins.valueOrNull?.length,
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
                    child: EmptyView(
                      message: 'まだ投稿はありません',
                      icon: Icons.place_outlined,
                    ),
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
              child: LoadingView(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: ErrorView(
                message: friendlyErrorMessage(e),
                onRetry: () => ref.invalidate(userPinsProvider(user.id)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
