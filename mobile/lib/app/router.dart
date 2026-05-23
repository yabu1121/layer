import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/map/map_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/pin_compose/pin_compose_screen.dart';
import '../features/signin/signin_screen.dart';
import '../features/splash/splash_screen.dart';
import 'main_shell.dart';
import 'placeholder_screen.dart';

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
      // 静的な /pin/compose を /pin/:id より先に置き、優先的にマッチさせる。
      GoRoute(
        path: '/pin/compose',
        builder: (context, state) => const PinComposeScreen(),
      ),
      GoRoute(
        path: '/pin/:id',
        builder: (context, state) =>
            PlaceholderScreen('PinDetail ${state.pathParameters['id']}'),
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
                builder: (context, state) =>
                    const PlaceholderScreen('Notifications'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) =>
                    const PlaceholderScreen('Profile'),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
