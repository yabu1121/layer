import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/friends/friends_screen.dart';
import '../features/map/map_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/pin_compose/pin_compose_screen.dart';
import '../features/pin_detail/pin_detail_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/signin/signin_screen.dart';
import '../features/splash/splash_screen.dart';
import 'main_shell.dart';

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
        builder: (context, state) => const FriendsScreen(),
      ),
      // 静的な /pin/compose を /pin/:id より先に置き、優先的にマッチさせる。
      GoRoute(
        path: '/pin/compose',
        builder: (context, state) => const PinComposeScreen(),
      ),
      GoRoute(
        path: '/pin/:id',
        builder: (context, state) =>
            PinDetailScreen(pinId: state.pathParameters['id']!),
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
