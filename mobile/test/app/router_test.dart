import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/app/router.dart';

void main() {
  testWidgets('各ルートに遷移して Placeholder を表示する', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // 初期ルート '/' は Splash。
    expect(find.text('Splash'), findsOneWidget);

    router.go('/signin');
    await tester.pumpAndSettle();
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
