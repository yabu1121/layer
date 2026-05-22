import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'signin_controller.dart';

/// Google アカウントでサインインする画面（screens.md §2.2 / issue #31）。
class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  static const _errorMessage = 'サインインに失敗しました。もう一度お試しください';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 失敗（AsyncError）になったらスナックバーで通知する。
    ref.listen<AsyncValue<void>>(signInControllerProvider, (previous, next) {
      if (next is AsyncError) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text(_errorMessage)));
      }
    });

    final isLoading = ref.watch(signInControllerProvider) is AsyncLoading;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Layer', style: theme.textTheme.displaySmall),
              const SizedBox(height: 16),
              Text(
                '舞台はタイムラインから、世界へ。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 48),
              FilledButton.icon(
                onPressed: isLoading ? null : () => _signIn(context, ref),
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('Google でサインイン'),
              ),
              const SizedBox(height: 24),
              Text(
                '続行すると利用規約とプライバシーポリシーに同意したものとみなされます',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    final ok =
        await ref.read(signInControllerProvider.notifier).signInWithGoogle();
    // 成功時のみ Splash に戻して再判定させる。失敗・キャンセルは留まる。
    if (ok && context.mounted) context.go('/');
  }
}
