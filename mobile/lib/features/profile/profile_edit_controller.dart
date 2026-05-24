import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/current_user.dart';
import '../../core/models/user.dart';

/// submit の結果。画面側が遷移・エラー表示を切り替えるために返す。
enum ProfileEditResult { invalid, success, userIdTaken, networkError }

/// copyWith で userIdError を「明示的に null へ」できるようにするセンチネル。
const _sentinel = Object();

/// プロフィール編集フォームの状態（US-A8 / FR-1.4）。
class ProfileEditState {
  const ProfileEditState({
    this.displayName = '',
    this.icon = '',
    this.userId = '',
    this.isSubmitting = false,
    this.userIdError,
    this.loaded = false,
  });

  final String displayName;
  final String icon;
  final String userId;
  final bool isSubmitting;
  final String? userIdError;

  /// currentUser から初期化済みか。
  final bool loaded;

  static final _userIdPattern = RegExp(r'^[a-zA-Z0-9_]{3,20}$');

  bool get isDisplayNameValid {
    final len = displayName.trim().runes.length;
    return len >= 1 && len <= 20;
  }

  bool get isUserIdFormatValid => _userIdPattern.hasMatch(userId);

  String? get displayNameErrorText {
    if (displayName.isEmpty) return null;
    return isDisplayNameValid ? null : '名前は20文字以内で入力してください';
  }

  String? get userIdErrorText {
    if (userIdError != null) return userIdError;
    if (userId.isEmpty) return null;
    return isUserIdFormatValid ? null : '英数字とアンダースコアの3〜20文字';
  }

  bool get isValid =>
      isDisplayNameValid &&
      isUserIdFormatValid &&
      userIdError == null &&
      icon.isNotEmpty;

  ProfileEditState copyWith({
    String? displayName,
    String? icon,
    String? userId,
    bool? isSubmitting,
    Object? userIdError = _sentinel,
    bool? loaded,
  }) {
    return ProfileEditState(
      displayName: displayName ?? this.displayName,
      icon: icon ?? this.icon,
      userId: userId ?? this.userId,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      userIdError: identical(userIdError, _sentinel)
          ? this.userIdError
          : userIdError as String?,
      loaded: loaded ?? this.loaded,
    );
  }
}

/// ProfileEditScreen のコントローラ（US-A8 / FR-1.4）。
class ProfileEditController extends Notifier<ProfileEditState> {
  @override
  ProfileEditState build() => const ProfileEditState();

  /// 既存プロフィールでフォームを初期化する。
  void load(User user) {
    state = ProfileEditState(
      displayName: user.displayName,
      icon: user.icon,
      userId: user.userId,
      loaded: true,
    );
  }

  void updateDisplayName(String value) =>
      state = state.copyWith(displayName: value);

  void updateIcon(String value) => state = state.copyWith(icon: value);

  /// user_id の編集時はサーバエラー（409）をクリアする。
  void updateUserId(String value) =>
      state = state.copyWith(userId: value, userIdError: null);

  /// プロフィールを更新する。成功で currentUser を更新し直す。
  Future<ProfileEditResult> submit() async {
    if (!state.isValid) return ProfileEditResult.invalid;
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
      ref.invalidate(currentUserProvider); // プロフィール表示を更新
      state = state.copyWith(isSubmitting: false);
      return ProfileEditResult.success;
    } on DioException catch (e) {
      state = state.copyWith(isSubmitting: false);
      if (e.response?.statusCode == 409) {
        state = state.copyWith(userIdError: 'このユーザーIDは既に使われています');
        return ProfileEditResult.userIdTaken;
      }
      return ProfileEditResult.networkError;
    }
  }
}

final profileEditControllerProvider =
    NotifierProvider<ProfileEditController, ProfileEditState>(
  ProfileEditController.new,
);
