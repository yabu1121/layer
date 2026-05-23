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
  });

  final FriendSearchStatus searchStatus;
  final PinAuthor? foundUser;
  final FriendRelation? relation;
  final bool isSending;

  FriendsState copyWith({
    FriendSearchStatus? searchStatus,
    PinAuthor? foundUser,
    FriendRelation? relation,
    bool? isSending,
  }) =>
      FriendsState(
        searchStatus: searchStatus ?? this.searchStatus,
        foundUser: foundUser ?? this.foundUser,
        relation: relation ?? this.relation,
        isSending: isSending ?? this.isSending,
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

  /// 入力のたびに 500ms デバウンスして検索する（画面用）。
  void onQueryChanged(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      state = const FriendsState();
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 500), () => search(q));
  }

  /// 即時検索（テスト・送信後の再判定でも使う）。
  Future<void> search(String userId) async {
    state = const FriendsState(searchStatus: FriendSearchStatus.loading);
    try {
      final user = await ref.read(friendRepositoryProvider).searchUser(userId);
      if (user == null) {
        state = const FriendsState(searchStatus: FriendSearchStatus.notFound);
        return;
      }
      final relation = await _relationFor(user);
      state = FriendsState(
        searchStatus: FriendSearchStatus.found,
        foundUser: user,
        relation: relation,
      );
    } catch (_) {
      state = const FriendsState(searchStatus: FriendSearchStatus.idle);
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
        state = FriendsState(
          searchStatus: FriendSearchStatus.found,
          foundUser: user,
          relation: FriendRelation.pending,
        );
        return true;
      case SendRequestResult.alreadyFriends:
        state = FriendsState(
          searchStatus: FriendSearchStatus.found,
          foundUser: user,
          relation: FriendRelation.friend,
        );
        return true;
      case SendRequestResult.error:
        state = state.copyWith(isSending: false);
        return false;
    }
  }
}

final friendsControllerProvider =
    NotifierProvider<FriendsController, FriendsState>(FriendsController.new);
