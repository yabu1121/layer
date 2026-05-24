import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_storage.dart';
import '../../core/auth/current_user.dart';
import '../../core/auth/google_auth.dart';

/// 自分のプロフィールとログアウト（screens.md §2.9）。
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('自分')),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          userAsync.when(
            data: (u) => Column(
              children: [
                Text(u.icon, style: const TextStyle(fontSize: 56)),
                const SizedBox(height: 8),
                Text(u.displayName, style: theme.textTheme.titleLarge),
                Text('@${u.userId}', style: theme.textTheme.bodyMedium),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) =>
                const Center(child: Text('プロフィールを取得できませんでした')),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: () => context.push('/friends'),
              icon: const Icon(Icons.group),
              label: const Text('友達を管理'),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => _confirmLogout(context, ref),
              icon: const Icon(Icons.logout),
              label: const Text('ログアウト'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) await _logout(context, ref);
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context); // await 前に取得（context の async 跨ぎ回避）
    // サーバはセッションを持たないが best-effort で通知。
    try {
      await ref.read(apiClientProvider).post<dynamic>('/api/auth/sign-out');
    } catch (_) {}
    // Google 側もサインアウト（次回の自動ログインを防ぐ）。
    try {
      await ref.read(googleAuthServiceProvider).signOut();
    } catch (_) {}
    await ref.read(authStorageProvider).clear();
    ref.invalidate(currentUserProvider);
    router.go('/'); // Splash → 未認証 → SignIn
  }
}
