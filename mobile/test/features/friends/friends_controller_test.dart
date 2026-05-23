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
  });

  PinAuthor? found;
  List<PinAuthor> friends;
  SendRequestResult sendResult;
  String? sentTo;

  @override
  Future<PinAuthor?> searchUser(String userId) async => found;

  @override
  Future<List<PinAuthor>> listFriends() async => friends;

  @override
  Future<SendRequestResult> sendRequest(String receiverId) async {
    sentTo = receiverId;
    return sendResult;
  }
}

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
}
