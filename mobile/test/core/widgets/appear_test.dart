import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/widgets/appear.dart';

void main() {
  testWidgets('Appear: 遅延後に子を表示する', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Appear(index: 2, child: Text('項目')),
      ),
    ));
    // 子は常にツリーに存在する（フェード中でも見つかる）。
    expect(find.text('項目'), findsOneWidget);
    await tester.pumpAndSettle(); // ディレイ＋アニメ完了
    expect(find.text('項目'), findsOneWidget);
  });
}
