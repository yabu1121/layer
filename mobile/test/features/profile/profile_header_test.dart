import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/features/profile/profile_header.dart';

void main() {
  testWidgets('アイコン・名前・ハンドル・投稿数を表示', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ProfileHeader(
          icon: '😎',
          displayName: 'リョウ',
          userId: 'riyo_1234',
          postCount: 7,
        ),
      ),
    ));
    expect(find.text('😎'), findsOneWidget);
    expect(find.text('リョウ'), findsOneWidget);
    expect(find.text('@riyo_1234'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('投稿'), findsOneWidget);
  });

  testWidgets('postCount が null なら投稿数を出さない', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ProfileHeader(icon: '🐱', displayName: 'X', userId: 'x'),
      ),
    ));
    expect(find.text('投稿'), findsNothing);
  });
}
