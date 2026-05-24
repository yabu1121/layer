import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/auth/current_user.dart';
import 'package:layer/core/location/geocoding_service.dart';
import 'package:layer/core/models/comment.dart';
import 'package:layer/core/models/pin.dart';
import 'package:layer/core/models/user.dart';
import 'package:layer/features/map/pin_repository.dart';
import 'package:layer/features/pin_detail/comment_repository.dart';
import 'package:layer/features/pin_detail/pin_detail_controller.dart';
import 'package:layer/features/pin_detail/reaction_repository.dart';

Pin _pin(String id) => Pin(
      id: id,
      ownerId: 'owner-$id',
      body: 'body-$id',
      lat: 35.0,
      lng: 139.0,
      createdAt: DateTime(2026, 1, 1),
      author: PinAuthor(
        id: 'owner-$id',
        userId: 'h$id',
        displayName: 'name-$id',
        icon: '🐱',
      ),
    );

class _FakePinRepo implements PinRepository {
  _FakePinRepo({this.nearbyById = const {}, this.throwIt = false});

  final Map<String, List<Pin>> nearbyById;
  bool throwIt;

  @override
  Future<Pin> getById(String id) async {
    if (throwIt) throw Exception('boom');
    return _pin(id);
  }

  @override
  Future<List<Pin>> getNearby(String id) async => nearbyById[id] ?? const [];

  @override
  Future<List<Pin>> fetchVisible({bool friendsOnly = false}) async => const [];
  @override
  Future<void> delete(String id) async {}
  @override
  Future<Pin> create({
    required String body,
    required double lat,
    required double lng,
    String? imageUrl,
  }) async =>
      throw UnimplementedError();
}

class _FakeGeocoding implements GeocodingService {
  @override
  Future<String?> reverseGeocode(double lat, double lng) async => '新宿御苑';
}

PinAuthor _author(String id, String icon) =>
    PinAuthor(id: id, userId: 'h$id', displayName: 'n$id', icon: icon);

class _FakeReactionRepo implements ReactionRepository {
  _FakeReactionRepo({List<PinAuthor>? initial}) : reactors = [...?initial];

  List<PinAuthor> reactors;
  bool throwIt = false;
  int addCalls = 0;
  int removeCalls = 0;

  @override
  Future<List<PinAuthor>> list(String pinId) async => List.of(reactors);

  @override
  Future<void> add(String pinId) async {
    if (throwIt) throw Exception('boom');
    addCalls++;
  }

  @override
  Future<void> removeMine(String pinId) async {
    if (throwIt) throw Exception('boom');
    removeCalls++;
  }
}

class _FakeCommentRepo implements CommentRepository {
  _FakeCommentRepo({List<Comment>? initial}) : items = [...?initial];

  List<Comment> items;
  bool throwIt = false;
  int seq = 0;

  @override
  Future<List<Comment>> list(String pinId) async => List.of(items);

  @override
  Future<Comment> create(String pinId, String body) async {
    if (throwIt) throw Exception('boom');
    final c = Comment(
      id: 'c${seq++}',
      body: body,
      createdAt: DateTime(2026, 1, 2),
      author: _author('me-id', '😀'),
    );
    items = [...items, c];
    return c;
  }

  @override
  Future<void> delete(String pinId, String commentId) async {
    if (throwIt) throw Exception('boom');
    items = items.where((c) => c.id != commentId).toList();
  }
}

Comment _comment(String id, String body, String authorId) => Comment(
      id: id,
      body: body,
      createdAt: DateTime(2026, 1, 2),
      author: _author(authorId, '🌸'),
    );

const _me = User(id: 'me-id', userId: 'me', displayName: 'Me', icon: '😀');

ProviderContainer _container(
  _FakePinRepo repo, {
  _FakeReactionRepo? reactions,
  _FakeCommentRepo? comments,
}) {
  final c = ProviderContainer(
    overrides: [
      pinRepositoryProvider.overrideWithValue(repo),
      geocodingServiceProvider.overrideWithValue(_FakeGeocoding()),
      reactionRepositoryProvider
          .overrideWithValue(reactions ?? _FakeReactionRepo()),
      commentRepositoryProvider
          .overrideWithValue(comments ?? _FakeCommentRepo()),
      currentUserProvider.overrideWith((ref) async => _me),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('load: メイン Pin・近傍・場所ラベルを取得する', () async {
    final repo = _FakePinRepo(nearbyById: {
      'p1': [_pin('p2'), _pin('p3')],
    });
    final c = _container(repo);
    await c.read(pinDetailControllerProvider.notifier).load('p1');
    final s = c.read(pinDetailControllerProvider);

    expect(s.status, PinDetailStatus.ready);
    expect(s.mainPin!.id, 'p1');
    expect(s.nearby.length, 2);
    expect(s.locationLabel, '新宿御苑');
    expect(s.totalCount, 3); // メイン + 近傍2
  });

  test('近傍 0 件: nearby は空、totalCount は 1', () async {
    final c = _container(_FakePinRepo());
    await c.read(pinDetailControllerProvider.notifier).load('p1');
    final s = c.read(pinDetailControllerProvider);
    expect(s.nearby, isEmpty);
    expect(s.totalCount, 1);
  });

  test('selectPin: 内容を差し替える', () async {
    final repo = _FakePinRepo(nearbyById: {
      'p1': [_pin('p2')],
    });
    final c = _container(repo);
    final n = c.read(pinDetailControllerProvider.notifier);
    await n.load('p1');
    expect(c.read(pinDetailControllerProvider).mainPin!.id, 'p1');

    await n.selectPin('p2');
    expect(c.read(pinDetailControllerProvider).mainPin!.id, 'p2');
  });

  test('失敗時は error', () async {
    final c = _container(_FakePinRepo(throwIt: true));
    await c.read(pinDetailControllerProvider.notifier).load('p1');
    expect(c.read(pinDetailControllerProvider).status, PinDetailStatus.error);
  });

  test('load: 共感者と自分を取得し reactedByMe を判定', () async {
    final reactions = _FakeReactionRepo(initial: [_author('me-id', '😀')]);
    final c = _container(_FakePinRepo(), reactions: reactions);
    await c.read(pinDetailControllerProvider.notifier).load('p1');
    final s = c.read(pinDetailControllerProvider);
    expect(s.reactionCount, 1);
    expect(s.reactedByMe, isTrue);
  });

  test('toggle: 未押下→楽観的に +1 して add する', () async {
    final reactions = _FakeReactionRepo(initial: [_author('other', '🌸')]);
    final c = _container(_FakePinRepo(), reactions: reactions);
    final n = c.read(pinDetailControllerProvider.notifier);
    await n.load('p1');
    expect(c.read(pinDetailControllerProvider).reactedByMe, isFalse);

    final ok = await n.toggleReaction();
    expect(ok, isTrue);
    final s = c.read(pinDetailControllerProvider);
    expect(s.reactedByMe, isTrue);
    expect(s.reactionCount, 2);
    expect(reactions.addCalls, 1);
  });

  test('toggle: 既押下→取消して removeMine する', () async {
    final reactions = _FakeReactionRepo(initial: [_author('me-id', '😀')]);
    final c = _container(_FakePinRepo(), reactions: reactions);
    final n = c.read(pinDetailControllerProvider.notifier);
    await n.load('p1');

    final ok = await n.toggleReaction();
    expect(ok, isTrue);
    final s = c.read(pinDetailControllerProvider);
    expect(s.reactedByMe, isFalse);
    expect(s.reactionCount, 0);
    expect(reactions.removeCalls, 1);
  });

  test('toggle: API 失敗でロールバックし false', () async {
    final reactions = _FakeReactionRepo()..throwIt = true;
    final c = _container(_FakePinRepo(), reactions: reactions);
    final n = c.read(pinDetailControllerProvider.notifier);
    await n.load('p1');
    expect(c.read(pinDetailControllerProvider).reactionCount, 0);

    final ok = await n.toggleReaction();
    expect(ok, isFalse);
    // ロールバックで元の 0 件に戻る。
    expect(c.read(pinDetailControllerProvider).reactionCount, 0);
    expect(c.read(pinDetailControllerProvider).reactedByMe, isFalse);
  });

  test('load: コメントを取得する', () async {
    final comments = _FakeCommentRepo(initial: [_comment('c1', 'やあ', 'x')]);
    final c = _container(_FakePinRepo(), comments: comments);
    await c.read(pinDetailControllerProvider.notifier).load('p1');
    expect(c.read(pinDetailControllerProvider).comments.single.body, 'やあ');
  });

  test('addComment: 成功で末尾に追加', () async {
    final c = _container(_FakePinRepo());
    final n = c.read(pinDetailControllerProvider.notifier);
    await n.load('p1');
    final ok = await n.addComment('はじめまして');
    expect(ok, isTrue);
    expect(c.read(pinDetailControllerProvider).comments.single.body, 'はじめまして');
  });

  test('addComment: 空文字は送らず false', () async {
    final c = _container(_FakePinRepo());
    final n = c.read(pinDetailControllerProvider.notifier);
    await n.load('p1');
    expect(await n.addComment('   '), isFalse);
    expect(c.read(pinDetailControllerProvider).comments, isEmpty);
  });

  test('deleteComment: 自分のを除く / canDeleteComment 判定', () async {
    final mine = _comment('c1', 'mine', 'me-id');
    final other = _comment('c2', 'other', 'x');
    final comments = _FakeCommentRepo(initial: [mine, other]);
    final c = _container(_FakePinRepo(), comments: comments);
    final n = c.read(pinDetailControllerProvider.notifier);
    await n.load('p1');
    expect(n.canDeleteComment(mine), isTrue);
    expect(n.canDeleteComment(other), isFalse);

    final ok = await n.deleteComment('c1');
    expect(ok, isTrue);
    expect(
      c.read(pinDetailControllerProvider).comments.map((e) => e.id).toList(),
      ['c2'],
    );
  });

  test('deleteComment: 失敗でロールバック', () async {
    final comments = _FakeCommentRepo(initial: [_comment('c1', 'mine', 'me-id')])
      ..throwIt = true;
    final c = _container(_FakePinRepo(), comments: comments);
    final n = c.read(pinDetailControllerProvider.notifier);
    await n.load('p1');
    final ok = await n.deleteComment('c1');
    expect(ok, isFalse);
    expect(c.read(pinDetailControllerProvider).comments.length, 1); // 巻き戻し
  });
}
