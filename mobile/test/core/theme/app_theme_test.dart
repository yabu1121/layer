import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/theme/app_theme.dart';

void main() {
  test('light: Material3 でシード由来の配色・体裁', () {
    final t = AppTheme.light();
    expect(t.useMaterial3, isTrue);
    expect(t.colorScheme.brightness, Brightness.light);
    expect(t.appBarTheme.centerTitle, isFalse);
  });

  test('dark: ダークの配色で同じ体裁', () {
    final t = AppTheme.dark();
    expect(t.useMaterial3, isTrue);
    expect(t.colorScheme.brightness, Brightness.dark);
    expect(t.appBarTheme.centerTitle, isFalse);
  });

  testWidgets('テーマ適用で主要ウィジェットがビルドできる', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          appBar: AppBar(title: const Text('タイトル')),
          body: Column(
            children: [
              FilledButton(onPressed: () {}, child: const Text('送信')),
              const Card(child: ListTile(title: Text('カード'))),
              const TextField(),
            ],
          ),
        ),
      ),
    );
    expect(find.text('タイトル'), findsOneWidget);
    expect(find.text('送信'), findsOneWidget);
    expect(find.text('カード'), findsOneWidget);
  });
}
