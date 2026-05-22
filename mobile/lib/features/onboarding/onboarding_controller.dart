import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

/// オンボーディングで選べる絵文字アイコン候補。
const onboardingIcons = <String>[
  '😊', '😎', '🌸', '🍀', '⭐', '🎵', '🐱', '🐶',
  '🌊', '🔥', '🍜', '📚', '⚽', '🎮', '🌍', '✈️',
];

/// submit の結果。画面側が遷移・エラー表示を切り替えるために返す。
enum OnboardingSubmitResult { invalid, success, userIdTaken, networkError }

/// 区別用センチネル（copyWith で userIdError を「明示的に null へ」できるように）。
const _sentinel = Object();

/// OnboardingScreen のフォーム状態。
class OnboardingFormState {
  const OnboardingFormState({
    required this.displayName,
    required this.icon,
    required this.userId,
    this.isSubmitting = false,
    this.userIdError,
  });

  final String displayName;
  final String icon;
  final String userId;
  final bool isSubmitting;

  /// user_id フィールドに表示するサーバ由来エラー（409 など）。
  final String? userIdError;

  static final _userIdPattern = RegExp(r'^[a-zA-Z0-9_]{3,20}$');

  bool get isDisplayNameValid {
    final len = displayName.trim().runes.length;
    return len >= 1 && len <= 20;
  }

  bool get isUserIdFormatValid => _userIdPattern.hasMatch(userId);

  /// 入力済みかつ長すぎる場合のみメッセージを返す（未入力時は無表示）。
  String? get displayNameErrorText {
    if (displayName.isEmpty) return null;
    return isDisplayNameValid ? null : '名前は20文字以内で入力してください';
  }

  /// user_id フィールドのエラー文（サーバエラー優先、次に書式）。
  String? get userIdErrorText {
    if (userIdError != null) return userIdError;
    if (userId.isEmpty) return null;
    return isUserIdFormatValid ? null : '英数字とアンダースコアの3〜20文字';
  }

  /// 「はじめる」を押せる条件。
  bool get isValid =>
      isDisplayNameValid &&
      isUserIdFormatValid &&
      userIdError == null &&
      icon.isNotEmpty;

  OnboardingFormState copyWith({
    String? displayName,
    String? icon,
    String? userId,
    bool? isSubmitting,
    Object? userIdError = _sentinel,
  }) {
    return OnboardingFormState(
      displayName: displayName ?? this.displayName,
      icon: icon ?? this.icon,
      userId: userId ?? this.userId,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      userIdError: identical(userIdError, _sentinel)
          ? this.userIdError
          : userIdError as String?,
    );
  }
}

/// OnboardingScreen のコントローラ（issue #32）。
class OnboardingController extends Notifier<OnboardingFormState> {
  @override
  OnboardingFormState build() => OnboardingFormState(
        displayName: '',
        icon: onboardingIcons.first,
        userId: _generateUserId(),
      );

  void updateDisplayName(String value) =>
      state = state.copyWith(displayName: value);

  void updateIcon(String value) => state = state.copyWith(icon: value);

  /// user_id の編集時はサーバエラー（409）をクリアする。
  void updateUserId(String value) =>
      state = state.copyWith(userId: value, userIdError: null);

  /// プロフィールを登録する。成功で /map へ遷移する想定。
  Future<OnboardingSubmitResult> submit() async {
    if (!state.isValid) return OnboardingSubmitResult.invalid;
    state = state.copyWith(isSubmitting: true, userIdError: null);
    try {
      // リクエストボディは snake_case（backend/internal/handler/me.go）。
      await ref.read(apiClientProvider).post<dynamic>(
        '/api/me/profile',
        data: {
          'display_name': state.displayName.trim(),
          'icon': state.icon,
          'user_id': state.userId,
        },
      );
      state = state.copyWith(isSubmitting: false);
      return OnboardingSubmitResult.success;
    } on DioException catch (e) {
      state = state.copyWith(isSubmitting: false);
      if (e.response?.statusCode == 409) {
        state = state.copyWith(userIdError: 'このユーザーIDは既に使われています');
        return OnboardingSubmitResult.userIdTaken;
      }
      return OnboardingSubmitResult.networkError;
    }
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingFormState>(
  OnboardingController.new,
);

/// 仮の user_id（`user_xxxxxx`）を生成する。ユーザーは変更できる。
String _generateUserId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rand = Random();
  final suffix =
      List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  return 'user_$suffix';
}
