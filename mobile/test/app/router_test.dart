import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/app/router.dart';
import 'package:layer/core/auth/auth_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('各ルートに遷移して Placeholder を表示する', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = AuthStorage(prefs); // トークン無し

    final container = ProviderContainer(
      overrides: [authStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // 初期ルート '/' の SplashScreen はトークン無しのため /signin へ自動遷移する。
    expect(find.text('SignIn'), findsOneWidget);

    router.go('/map');
    await tester.pumpAndSettle();
    expect(find.text('Map'), findsOneWidget);

    // 静的ルート /pin/compose が /pin/:id より優先される。
    router.go('/pin/compose');
    await tester.pumpAndSettle();
    expect(find.text('PinCompose'), findsOneWidget);

    // 動的パラメータ付きルート。
    router.go('/pin/abc123');
    await tester.pumpAndSettle();
    expect(find.text('PinDetail abc123'), findsOneWidget);
  });
}
