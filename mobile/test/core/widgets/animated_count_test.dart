import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/widgets/animated_count.dart';

void main() {
  testWidgets('カウントアップ後に最終値を表示する', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AnimatedCount(value: 42)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
  });
}
