import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/widgets/error_view.dart';

void main() {
  testWidgets('メッセージと再試行ボタンを表示し、タップでコールバック', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ErrorView(message: 'ネットに繋いでね', onRetry: () => tapped++),
      ),
    ));

    expect(find.text('ネットに繋いでね'), findsOneWidget);
    expect(find.text('再試行'), findsOneWidget);

    await tester.tap(find.text('再試行'));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('onRetry が無ければ再試行ボタンを出さない', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ErrorView(message: 'エラー')),
    ));
    expect(find.text('エラー'), findsOneWidget);
    expect(find.text('再試行'), findsNothing);
  });
}
