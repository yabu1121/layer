import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/auth/current_user.dart';
import 'package:layer/core/location/geocoding_service.dart';
import 'package:layer/core/models/comment.dart';
import 'package:layer/core/models/pin.dart';
import 'package:layer/core/models/user.dart';
import 'package:layer/features/map/pin_repository.dart';
import 'package:layer/features/pin_detail/comment_repository.dart';
import 'package:layer/features/pin_detail/pin_detail_screen.dart';
import 'package:layer/features/pin_detail/reaction_repository.dart';

Pin _pin(String id, {String? imageUrl}) => Pin(
      id: id,
      ownerId: 'o$id',
      body: 'body-$id',
      lat: 35.0,
      lng: 139.0,
      createdAt: DateTime(2026, 1, 1),
      author: PinAuthor(
        id: 'o$id',
        userId: 'h$id',
        displayName: 'name-$id',
        icon: '🐱',
      ),
      imageUrl: imageUrl,
    );

class _FakePinRepo implements PinRepository {
  _FakePinRepo(this.nearby, {this.mainImageUrl});
  final List<Pin> nearby;
  final String? mainImageUrl;

  @override
  Future<Pin> getById(String id) async => _pin(id, imageUrl: mainImageUrl);
  @override
  Future<List<Pin>> getNearby(String id) async => nearby;
  @override
  Future<List<Pin>> fetchVisible({bool friendsOnly = false}) async => const [];
  @override
  Future<void> delete(String id) async {}
  @override
  Future<Pin> create({
    required String body,
    required double lat,
    required double lng,
  }) async =>
      throw UnimplementedError();
}

class _FakeGeocoding implements GeocodingService {
  @override
  Future<String?> reverseGeocode(double lat, double lng) async => '新宿御苑';
}

class _FakeReaction implements ReactionRepository {
  @override
  Future<List<PinAuthor>> list(String pinId) async => const [];
  @override
  Future<void> add(String pinId) async {}
  @override
  Future<void> removeMine(String pinId) async {}
}

class _FakeCommentRepo implements CommentRepository {
  _FakeCommentRepo({List<Comment>? initial}) : items = [...?initial];

  List<Comment> items;
  int seq = 0;

  @override
  Future<List<Comment>> list(String pinId) async => List.of(items);

  @override
  Future<Comment> create(String pinId, String body) async {
    final c = Comment(
      id: 'new${seq++}',
      body: body,
      createdAt: DateTime(2026, 1, 2),
      author: const PinAuthor(
          id: 'me', userId: 'me', displayName: 'Me', icon: '😀'),
    );
    items = [...items, c];
    return c;
  }

  @override
  Future<void> delete(String pinId, String commentId) async {
    items = items.where((c) => c.id != commentId).toList();
  }
}

Widget _app(List<Pin> nearby,
        {_FakeCommentRepo? comments, String? mainImageUrl}) =>
    ProviderScope(
      overrides: [
        pinRepositoryProvider
            .overrideWithValue(_FakePinRepo(nearby, mainImageUrl: mainImageUrl)),
        geocodingServiceProvider.overrideWithValue(_FakeGeocoding()),
        reactionRepositoryProvider.overrideWithValue(_FakeReaction()),
        commentRepositoryProvider
            .overrideWithValue(comments ?? _FakeCommentRepo()),
        currentUserProvider.overrideWith(
          (ref) async => const User(
            id: 'me',
            userId: 'me',
            displayName: 'Me',
            icon: '😀',
          ),
        ),
      ],
      child: const MaterialApp(home: PinDetailScreen(pinId: 'p1')),
    );

void main() {
  testWidgets('メイン Pin と近傍を表示する', (tester) async {
    await tester.pumpWidget(_app([_pin('p2')]));
    await tester.pumpAndSettle();

    expect(find.text('新宿御苑'), findsOneWidget);
    expect(find.text('body-p1'), findsOneWidget); // メイン
    expect(find.text('── 同じ場所の Pin ──'), findsOneWidget);
    expect(find.textContaining('わかる'), findsWidgets); // ボタン表示

    // 近傍カードは下にあるためスクロールして確認する。
    await tester.scrollUntilVisible(
      find.text('body-p2'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('body-p2'), findsOneWidget); // 近傍
  });

  testWidgets('近傍 0 件で空メッセージ', (tester) async {
    await tester.pumpWidget(_app(const []));
    await tester.pumpAndSettle();

    expect(find.text('body-p1'), findsOneWidget);
    expect(find.text('ここではまだあなただけです'), findsOneWidget);
  });

  testWidgets('imageUrl があれば画像を表示する', (tester) async {
    await tester.pumpWidget(
      _app(const [], mainImageUrl: 'https://cdn.example/r2/x.jpg'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('imageUrl が無ければ画像を表示しない', (tester) async {
    await tester.pumpWidget(_app(const []));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('コメントを一覧表示し、投稿で即時反映する', (tester) async {
    final repo = _FakeCommentRepo(initial: [
      Comment(
        id: 'c1',
        body: 'こんにちは',
        createdAt: DateTime(2026, 1, 2),
        author: const PinAuthor(
            id: 'x', userId: 'hx', displayName: 'X', icon: '🌸'),
      ),
    ]);
    await tester.pumpWidget(_app(const [], comments: repo));
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(find.text('こんにちは'), 200,
        scrollable: scrollable);
    expect(find.text('こんにちは'), findsOneWidget);

    // 入力欄まで送り、IME の送信アクションで投稿する（シートのドラッグ判定を避ける）。
    await tester.scrollUntilVisible(find.byType(TextField), 200,
        scrollable: scrollable);
    await tester.enterText(find.byType(TextField), 'やあ');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.text('やあ'), findsOneWidget);
  });
}
