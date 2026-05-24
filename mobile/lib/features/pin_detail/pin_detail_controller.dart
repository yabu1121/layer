import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/current_user.dart';
import '../../core/location/geocoding_service.dart';
import '../../core/models/comment.dart';
import '../../core/models/pin.dart';
import '../map/pin_repository.dart';
import 'comment_repository.dart';
import 'reaction_repository.dart';

enum PinDetailStatus { loading, ready, error }

class PinDetailState {
  const PinDetailState({
    this.status = PinDetailStatus.loading,
    this.mainPin,
    this.nearby = const [],
    this.locationLabel,
    this.reactors = const [],
    this.comments = const [],
    this.myAuthor,
  });

  final PinDetailStatus status;
  final Pin? mainPin;
  final List<Pin> nearby;
  final String? locationLabel;

  /// メイン Pin の共感者（自分を含む場合あり）。
  final List<PinAuthor> reactors;

  /// メイン Pin のコメント（古い順）。
  final List<Comment> comments;

  /// 自分の公開プロフィール（楽観的更新で reactors に差し込む / 自分判定に使う）。
  final PinAuthor? myAuthor;

  int get totalCount => (mainPin == null ? 0 : 1) + nearby.length;
  int get reactionCount => reactors.length;
  bool get reactedByMe =>
      myAuthor != null && reactors.any((r) => r.id == myAuthor!.id);

  PinDetailState copyWith({
    PinDetailStatus? status,
    Pin? mainPin,
    List<Pin>? nearby,
    String? locationLabel,
    List<PinAuthor>? reactors,
    List<Comment>? comments,
    PinAuthor? myAuthor,
  }) =>
      PinDetailState(
        status: status ?? this.status,
        mainPin: mainPin ?? this.mainPin,
        nearby: nearby ?? this.nearby,
        locationLabel: locationLabel ?? this.locationLabel,
        reactors: reactors ?? this.reactors,
        comments: comments ?? this.comments,
        myAuthor: myAuthor ?? this.myAuthor,
      );
}

/// PinDetailScreen のコントローラ（issue #38・#39）。
class PinDetailController extends Notifier<PinDetailState> {
  @override
  PinDetailState build() => const PinDetailState();

  Future<void> load(String pinId) async {
    state = const PinDetailState();
    try {
      final repo = ref.read(pinRepositoryProvider);
      final pin = await repo.getById(pinId);
      final nearby = await repo.getNearby(pinId);

      // 場所ラベルはベストエフォート（geocoding は Web 非対応のことがある）。
      String? label;
      try {
        label = await ref
            .read(geocodingServiceProvider)
            .reverseGeocode(pin.lat, pin.lng);
      } catch (_) {}

      // 共感と自分の情報もベストエフォート（失敗しても詳細は表示する）。
      var reactors = <PinAuthor>[];
      try {
        reactors = await ref.read(reactionRepositoryProvider).list(pinId);
      } catch (_) {}
      var comments = <Comment>[];
      try {
        comments = await ref.read(commentRepositoryProvider).list(pinId);
      } catch (_) {}
      PinAuthor? me;
      try {
        final user = await ref.read(currentUserProvider.future);
        me = PinAuthor(
          id: user.id,
          userId: user.userId,
          displayName: user.displayName,
          icon: user.icon,
        );
      } catch (_) {}

      state = PinDetailState(
        status: PinDetailStatus.ready,
        mainPin: pin,
        nearby: nearby,
        locationLabel: label,
        reactors: reactors,
        comments: comments,
        myAuthor: me,
      );
    } catch (_) {
      state = const PinDetailState(status: PinDetailStatus.error);
    }
  }

  Future<void> selectPin(String pinId) => load(pinId);

  /// 自分かどうか（メイン Pin の削除可否）。
  bool get canDeleteMain {
    final me = state.myAuthor;
    final pin = state.mainPin;
    return me != null && pin != null && pin.isMine(me.id);
  }

  /// メイン Pin（自分の投稿）を削除する。成功で true。
  Future<bool> deleteMain() async {
    final pin = state.mainPin;
    if (pin == null) return false;
    try {
      await ref.read(pinRepositoryProvider).delete(pin.id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 「わかる」をトグルする。楽観的に reactors を更新し、API 失敗で巻き戻す。
  /// 成功で true、失敗（要再試行）で false を返す。
  Future<bool> toggleReaction() async {
    final current = state;
    final me = current.myAuthor;
    final pin = current.mainPin;
    if (me == null || pin == null) return false;

    final wasReacted = current.reactedByMe;
    final previous = current.reactors;
    final optimistic = wasReacted
        ? previous.where((r) => r.id != me.id).toList()
        : [...previous, me];
    state = current.copyWith(reactors: optimistic);

    try {
      final repo = ref.read(reactionRepositoryProvider);
      if (wasReacted) {
        await repo.removeMine(pin.id);
      } else {
        await repo.add(pin.id);
      }
      return true;
    } catch (_) {
      state = state.copyWith(reactors: previous); // ロールバック
      return false;
    }
  }

  /// コメントを投稿する。成功で末尾に追加し true。空文字や失敗で false。
  Future<bool> addComment(String body) async {
    final text = body.trim();
    final pin = state.mainPin;
    if (text.isEmpty || pin == null) return false;
    try {
      final created =
          await ref.read(commentRepositoryProvider).create(pin.id, text);
      state = state.copyWith(comments: [...state.comments, created]);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 自分のコメントを削除する。楽観的に除き、API 失敗で巻き戻す。
  Future<bool> deleteComment(String commentId) async {
    final pin = state.mainPin;
    if (pin == null) return false;
    final previous = state.comments;
    state = state.copyWith(
      comments: previous.where((c) => c.id != commentId).toList(),
    );
    try {
      await ref.read(commentRepositoryProvider).delete(pin.id, commentId);
      return true;
    } catch (_) {
      state = state.copyWith(comments: previous); // ロールバック
      return false;
    }
  }

  /// 自分のコメントか（削除可否）。
  bool canDeleteComment(Comment c) {
    final me = state.myAuthor;
    return me != null && c.isMine(me.id);
  }
}

final pinDetailControllerProvider =
    NotifierProvider<PinDetailController, PinDetailState>(
  PinDetailController.new,
);
