import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/auth/current_user.dart';
import 'package:layer/core/models/pin.dart';
import 'package:layer/core/models/user.dart';
import 'package:layer/features/friends/friend_repository.dart';
import 'package:layer/features/friends/friends_controller.dart';

PinAuthor _user(String id) =>
    PinAuthor(id: id, userId: 'h$id', displayName: 'n$id', icon: '🌸');

class _FakeFriendRepo implements FriendRepository {
  _FakeFriendRepo({
    this.found,
    this.friends = const [],
    this.sendResult = SendRequestResult.sent,
    this.incoming = const [],
  });

  PinAuthor? found;
  List<PinAuthor> friends;
  SendRequestResult sendResult;
  List<IncomingRequest> incoming;
  String? sentTo;
  String? acceptedId;
  String? rejectedId;
  bool throwAccept = false;

  @override
  Future<PinAuthor?> searchUser(String userId) async => found;

  @override
  Future<List<PinAuthor>> listFriends() async => friends;

  @override
  Future<SendRequestResult> sendRequest(String receiverId) async {
    sentTo = receiverId;
    return sendResult;
  }

  @override
  Future<List<IncomingRequest>> listIncoming() async => incoming;

  @override
  Future<void> accept(String requestId) async {
    if (throwAccept) throw Exception('boom');
    acceptedId = requestId;
  }

  @override
  Future<void> reject(String requestId) async {
    rejectedId = requestId;
  }
}

IncomingRequest _req(String id, String userId) =>
    IncomingRequest(id: id, requester: _user(userId));

const _me = User(id: 'me-id', userId: 'me', displayName: 'Me', icon: '😀');

ProviderContainer _container(_FakeFriendRepo repo) {
  final c = ProviderContainer(
    overrides: [
      friendRepositoryProvider.overrideWithValue(repo),
      currentUserProvider.overrideWith((ref) async => _me),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('検索: 他人 → available', () async {
    final c = _container(_FakeFriendRepo(found: _user('other')));
    await c.read(friendsControllerProvider.notifier).search('hother');
    final s = c.read(friendsControllerProvider);
    expect(s.searchStatus, FriendSearchStatus.found);
    expect(s.relation, FriendRelation.available);
  });

  test('検索: 自分 → self', () async {
    final c = _container(_FakeFriendRepo(found: _user('me-id')));
    await c.read(friendsControllerProvider.notifier).search('me');
    expect(c.read(friendsControllerProvider).relation, FriendRelation.self);
  });

  test('検索: 既存友達 → friend', () async {
    final repo = _FakeFriendRepo(found: _user('f1'), friends: [_user('f1')]);
    final c = _container(repo);
    await c.read(friendsControllerProvider.notifier).search('hf1');
    expect(c.read(friendsControllerProvider).relation, FriendRelation.friend);
  });

  test('検索: 不在 → notFound', () async {
    final c = _container(_FakeFriendRepo(found: null));
    await c.read(friendsControllerProvider.notifier).search('none');
    expect(
      c.read(friendsControllerProvider).searchStatus,
      FriendSearchStatus.notFound,
    );
  });

  test('申請送信: sent → pending、receiver_id を渡す', () async {
    final repo = _FakeFriendRepo(found: _user('other'));
    final c = _container(repo);
    final n = c.read(friendsControllerProvider.notifier);
    await n.search('hother');

    final ok = await n.sendRequest();
    expect(ok, isTrue);
    expect(repo.sentTo, 'other');
    expect(c.read(friendsControllerProvider).relation, FriendRelation.pending);
  });

  test('申請送信: already_friends → friend 表示', () async {
    final repo = _FakeFriendRepo(
      found: _user('other'),
      sendResult: SendRequestResult.alreadyFriends,
    );
    final c = _container(repo);
    final n = c.read(friendsControllerProvider.notifier);
    await n.search('hother');
    await n.sendRequest();
    expect(c.read(friendsControllerProvider).relation, FriendRelation.friend);
  });

  test('申請送信: error → false', () async {
    final repo = _FakeFriendRepo(
      found: _user('other'),
      sendResult: SendRequestResult.error,
    );
    final c = _container(repo);
    final n = c.read(friendsControllerProvider.notifier);
    await n.search('hother');
    expect(await n.sendRequest(), isFalse);
  });

  test('loadLists: 受信申請と友達一覧を読み込む', () async {
    final repo = _FakeFriendRepo(
      incoming: [_req('r1', 'a'), _req('r2', 'b')],
      friends: [_user('f1')],
    );
    final c = _container(repo);
    await c.read(friendsControllerProvider.notifier).loadLists();
    final s = c.read(friendsControllerProvider);
    expect(s.incoming.length, 2);
    expect(s.friends.length, 1);
  });

  test('accept: incoming から外して friends に移す', () async {
    final repo = _FakeFriendRepo(incoming: [_req('r1', 'a')]);
    final c = _container(repo);
    final n = c.read(friendsControllerProvider.notifier);
    await n.loadLists();

    final ok = await n.accept(_req('r1', 'a'));
    expect(ok, isTrue);
    expect(repo.acceptedId, 'r1');
    final s = c.read(friendsControllerProvider);
    expect(s.incoming, isEmpty);
    expect(s.friends.any((f) => f.id == 'a'), isTrue);
  });

  test('accept 失敗: ロールバック', () async {
    final repo = _FakeFriendRepo(incoming: [_req('r1', 'a')])..throwAccept = true;
    final c = _container(repo);
    final n = c.read(friendsControllerProvider.notifier);
    await n.loadLists();

    final ok = await n.accept(_req('r1', 'a'));
    expect(ok, isFalse);
    expect(c.read(friendsControllerProvider).incoming.length, 1); // 戻る
  });

  test('reject: incoming から外す', () async {
    final repo = _FakeFriendRepo(incoming: [_req('r1', 'a'), _req('r2', 'b')]);
    final c = _container(repo);
    final n = c.read(friendsControllerProvider.notifier);
    await n.loadLists();

    await n.reject(_req('r1', 'a'));
    expect(repo.rejectedId, 'r1');
    final s = c.read(friendsControllerProvider);
    expect(s.incoming.length, 1);
    expect(s.incoming.first.id, 'r2');
  });

  test('inviteMessage: 自分の user_id を含む', () async {
    final c = _container(_FakeFriendRepo());
    final msg = await c.read(friendsControllerProvider.notifier).inviteMessage();
    expect(msg, 'Layer で繋がろう！ @me を友達追加してね');
  });

  test('検索しても incoming/friends は保持される', () async {
    final repo = _FakeFriendRepo(
      incoming: [_req('r1', 'a')],
      friends: [_user('f1')],
      found: _user('other'),
    );
    final c = _container(repo);
    final n = c.read(friendsControllerProvider.notifier);
    await n.loadLists();
    await n.search('hother');
    final s = c.read(friendsControllerProvider);
    expect(s.searchStatus, FriendSearchStatus.found);
    expect(s.incoming.length, 1); // 検索で消えない
  });
}
