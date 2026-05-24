import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'splash_controller.dart';

/// 起動画面。認証状態をチェックし、適切な画面へ振り分ける（screens.md §2.1）。
/// 中央にロゴ、判定中はローディング、失敗時は再試行ボタンを表示する。
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 判定が確定したら遷移する。build 中の navigation を避けるため listen で行う。
    ref.listen<AsyncValue<SplashDestination>>(splashDestinationProvider,
        (previous, next) {
      next.whenOrNull(
        data: (destination) {
          switch (destination) {
            case SplashDestination.signIn:
              context.go('/signin');
            case SplashDestination.onboarding:
              context.go('/onboarding');
            case SplashDestination.map:
              context.go('/map');
          }
        },
      );
    });

    final state = ref.watch(splashDestinationProvider);
    return Scaffold(
      body: Center(
        child: switch (state) {
          AsyncError() => _ErrorBody(
              onRetry: () => ref.invalidate(splashDestinationProvider),
            ),
          _ => const _LoadingBody(),
        },
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AnimatedLogo(),
        SizedBox(height: 24),
        CircularProgressIndicator(),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _AnimatedLogo(),
        const SizedBox(height: 16),
        const Text('接続に失敗しました'),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('再試行')),
      ],
    );
  }
}

/// 起動時にフェード＋スケールで登場するロゴ。
class _AnimatedLogo extends StatefulWidget {
  const _AnimatedLogo();

  @override
  State<_AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<_AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<double> _scale = Tween<double>(begin: 0.8, end: 1.0)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Text('Layer', style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}
