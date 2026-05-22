import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/auth/auth_storage.dart';
import 'package:layer/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('LayerApp はトークン無しのとき SignIn へ振り分ける',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const LayerApp(),
      ),
    );
    await tester.pumpAndSettle();

    // SplashScreen → トークン無し → /signin（Placeholder）。
    expect(find.text('SignIn'), findsOneWidget);
  });
}
