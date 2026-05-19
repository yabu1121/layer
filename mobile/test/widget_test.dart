import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:layer/main.dart';

void main() {
  testWidgets('LayerApp renders title', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: LayerApp()));

    expect(find.text('Layer'), findsOneWidget);
  });
}
