import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/onboarding/onboarding_screen.dart';
import '../features/signin/signin_screen.dart';
import '../features/splash/splash_screen.dart';
import 'placeholder_screen.dart';

/// アプリ全体のルーティング定義。
///
/// 全 9 画面（require.md / docs/design/screens.md）のルート枠を用意する。
/// 各画面の中身は後続 issue で実装するため、現状は [PlaceholderScreen] を返す。
/// 認証状態によるリダイレクトも後続 issue（#30 Splash）で追加する。
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
      GoRoute(
        path: '/map',
        builder: (context, state) => const PlaceholderScreen('Map'),
      ),
      GoRoute(
        path: '/friends',
        builder: (context, state) => const PlaceholderScreen('Friends'),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) =>
            const PlaceholderScreen('Notifications'),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const PlaceholderScreen('Profile'),
      ),
      // 静的な /pin/compose を /pin/:id より先に置き、優先的にマッチさせる。
      GoRoute(
        path: '/pin/compose',
        builder: (context, state) => const PlaceholderScreen('PinCompose'),
      ),
      GoRoute(
        path: '/pin/:id',
        builder: (context, state) =>
            PlaceholderScreen('PinDetail ${state.pathParameters['id']}'),
      ),
    ],
  );
});
