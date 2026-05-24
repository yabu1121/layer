import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/widgets/empty_view.dart';
import 'package:layer/core/widgets/loading_view.dart';

void main() {
  testWidgets('EmptyView: メッセージとヒントを表示', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: EmptyView(message: 'まだありません', hint: '追加してみよう'),
      ),
    ));
    expect(find.text('まだありません'), findsOneWidget);
    expect(find.text('追加してみよう'), findsOneWidget);
  });

  testWidgets('EmptyView: hint なしならヒント行を出さない', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: EmptyView(message: '空です')),
    ));
    expect(find.text('空です'), findsOneWidget);
  });

  testWidgets('LoadingView: インジケータと任意メッセージ', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: LoadingView(message: '読み込み中')),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('読み込み中'), findsOneWidget);
  });
}
