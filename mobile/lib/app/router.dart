import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models/pin.dart';
import '../core/models/user.dart';
import '../features/friends/friends_screen.dart';
import '../features/map/map_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/pin_compose/pin_compose_screen.dart';
import '../features/pin_detail/pin_detail_screen.dart';
import '../features/profile/profile_edit_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/user_profile_screen.dart';
import '../features/signin/signin_screen.dart';
import '../features/splash/splash_screen.dart';
import 'main_shell.dart';

/// push 系ルート共通のトランジション（フェード＋わずかな下からのスライド）。
CustomTransitionPage<void> _fadeSlidePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// アプリ全体のルーティング定義。
///
/// 認証フロー（/, /signin, /onboarding）と Pin 全画面（/pin/*）はトップレベル、
/// メインの 3 画面（/map, /notifications, /profile）は [StatefulShellRoute] で
/// ボトムタブとして束ねる（タブ間で状態を保持）。
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/signin',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      // 友達画面（プロフィールから push して開く全画面）。
      GoRoute(
        path: '/friends',
        pageBuilder: (context, state) =>
            _fadeSlidePage(state, const FriendsScreen()),
      ),
      // プロフィール編集（プロフィールから extra で User を渡して push）。
      GoRoute(
        path: '/profile/edit',
        pageBuilder: (context, state) {
          final user = state.extra as User?;
          final child = user == null
              ? const Scaffold(
                  body: Center(child: Text('プロフィール情報がありません')),
                )
              : ProfileEditScreen(user: user);
          return _fadeSlidePage(state, child);
        },
      ),
      // 他ユーザーのプロフィール（友達一覧などから extra で PinAuthor を渡す）。
      GoRoute(
        path: '/users/:id',
        pageBuilder: (context, state) {
          final user = state.extra as PinAuthor?;
          final child = user == null
              ? const Scaffold(
                  body: Center(child: Text('ユーザー情報がありません')),
                )
              : UserProfileScreen(user: user);
          return _fadeSlidePage(state, child);
        },
      ),
      // 静的な /pin/compose を /pin/:id より先に置き、優先的にマッチさせる。
      GoRoute(
        path: '/pin/compose',
        pageBuilder: (context, state) =>
            _fadeSlidePage(state, const PinComposeScreen()),
      ),
      GoRoute(
        path: '/pin/:id',
        pageBuilder: (context, state) => _fadeSlidePage(
          state,
          PinDetailScreen(pinId: state.pathParameters['id']!),
        ),
      ),
      // ボトムタブ（地図 / 通知 / 自分）。
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                builder: (context, state) => const MapScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notifications',
                builder: (context, state) => const NotificationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
