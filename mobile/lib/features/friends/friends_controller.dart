import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/current_user.dart';
import '../../core/models/pin.dart';
import 'friend_repository.dart';

enum FriendSearchStatus { idle, loading, notFound, found }

/// 検索したユーザーと自分の関係。
enum FriendRelation { available, pending, friend, self }

class FriendsState {
  const FriendsState({
    this.searchStatus = FriendSearchStatus.idle,
    this.foundUser,
    this.relation,
    this.isSending = false,
    this.incoming = const [],
    this.friends = const [],
  });

  final FriendSearchStatus searchStatus;
  final PinAuthor? foundUser;
  final FriendRelation? relation;
  final bool isSending;

  /// 受信した友達申請（#41）。
  final List<IncomingRequest> incoming;

  /// accepted な友達一覧（#41 で承認時に追加、表示は #42）。
  final List<PinAuthor> friends;

  FriendsState copyWith({
    FriendSearchStatus? searchStatus,
    PinAuthor? foundUser,
    FriendRelation? relation,
    bool? isSending,
    List<IncomingRequest>? incoming,
    List<PinAuthor>? friends,
  }) =>
      FriendsState(
        searchStatus: searchStatus ?? this.searchStatus,
        foundUser: foundUser ?? this.foundUser,
        relation: relation ?? this.relation,
        isSending: isSending ?? this.isSending,
        incoming: incoming ?? this.incoming,
        friends: friends ?? this.friends,
      );
}

/// FriendsScreen の検索・申請コントローラ（issue #40）。
class FriendsController extends Notifier<FriendsState> {
  Timer? _debounce;

  @override
  FriendsState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const FriendsState();
  }

  /// 受信申請と友達一覧を取得する（画面の初期化で呼ぶ）。
  Future<void> loadLists() async {
    final repo = ref.read(friendRepositoryProvider);
    try {
      final incoming = await repo.listIncoming();
      final friends = await repo.listFriends();
      state = state.copyWith(incoming: incoming, friends: friends);
    } catch (_) {
      // 取得失敗時は現状維持。
    }
  }

  /// 入力のたびに 500ms デバウンスして検索する（画面用）。
  void onQueryChanged(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      state = state.copyWith(searchStatus: FriendSearchStatus.idle);
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 500), () => search(q));
  }

  /// 即時検索（テスト・送信後の再判定でも使う）。
  Future<void> search(String userId) async {
    state = state.copyWith(searchStatus: FriendSearchStatus.loading);
    try {
      final user = await ref.read(friendRepositoryProvider).searchUser(userId);
      if (user == null) {
        state = state.copyWith(searchStatus: FriendSearchStatus.notFound);
        return;
      }
      final relation = await _relationFor(user);
      state = state.copyWith(
        searchStatus: FriendSearchStatus.found,
        foundUser: user,
        relation: relation,
      );
    } catch (_) {
      state = state.copyWith(searchStatus: FriendSearchStatus.idle);
    }
  }

  Future<FriendRelation> _relationFor(PinAuthor user) async {
    try {
      final me = await ref.read(currentUserProvider.future);
      if (user.id == me.id) return FriendRelation.self;
    } catch (_) {}
    try {
      final friends = await ref.read(friendRepositoryProvider).listFriends();
      if (friends.any((f) => f.id == user.id)) return FriendRelation.friend;
    } catch (_) {}
    return FriendRelation.available;
  }

  /// 申請を送る。成功（または既に申請済/友達）で true、失敗で false。
  Future<bool> sendRequest() async {
    final user = state.foundUser;
    if (user == null) return false;
    state = state.copyWith(isSending: true);
    final result =
        await ref.read(friendRepositoryProvider).sendRequest(user.id);
    switch (result) {
      case SendRequestResult.sent:
      case SendRequestResult.alreadyRequested:
        state = state.copyWith(
            relation: FriendRelation.pending, isSending: false);
        return true;
      case SendRequestResult.alreadyFriends:
        state = state.copyWith(
            relation: FriendRelation.friend, isSending: false);
        return true;
      case SendRequestResult.error:
        state = state.copyWith(isSending: false);
        return false;
    }
  }

  /// 申請を承認する。楽観的に incoming から外して friends に移し、失敗で巻き戻す。
  Future<bool> accept(IncomingRequest request) async {
    final prevIncoming = state.incoming;
    final prevFriends = state.friends;
    state = state.copyWith(
      incoming: prevIncoming.where((r) => r.id != request.id).toList(),
      friends: [...prevFriends, request.requester],
    );
    try {
      await ref.read(friendRepositoryProvider).accept(request.id);
      return true;
    } catch (_) {
      state = state.copyWith(incoming: prevIncoming, friends: prevFriends);
      return false;
    }
  }

  /// 招待用の共有テキストを生成する（自分の user_id を含む）。取得失敗で null。
  Future<String?> inviteMessage() async {
    try {
      final me = await ref.read(currentUserProvider.future);
      return 'Layer で繋がろう！ @${me.userId} を友達追加してね';
    } catch (_) {
      return null;
    }
  }

  /// 申請を拒否する。楽観的に incoming から外し、失敗で巻き戻す。
  Future<bool> reject(IncomingRequest request) async {
    final prevIncoming = state.incoming;
    state = state.copyWith(
      incoming: prevIncoming.where((r) => r.id != request.id).toList(),
    );
    try {
      await ref.read(friendRepositoryProvider).reject(request.id);
      return true;
    } catch (_) {
      state = state.copyWith(incoming: prevIncoming);
      return false;
    }
  }
}

final friendsControllerProvider =
    NotifierProvider<FriendsController, FriendsState>(FriendsController.new);
