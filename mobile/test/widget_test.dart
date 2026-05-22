import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/auth/auth_storage.dart';
import 'package:layer/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('LayerApp は初期ルートで Splash を表示する', (WidgetTester tester) async {
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

    expect(find.text('Splash'), findsOneWidget);
  });
}
