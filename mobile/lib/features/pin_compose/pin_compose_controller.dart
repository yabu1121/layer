import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location/geocoding_service.dart';
import '../../core/location/location_service.dart';
import '../map/pin_repository.dart';

enum PinComposeResult { invalid, success, error }

/// Pin 投稿フォームの状態。
class PinComposeState {
  const PinComposeState({
    this.lat,
    this.lng,
    this.locationLabel,
    this.body = '',
    this.isLocating = true,
    this.isSubmitting = false,
  });

  final double? lat;
  final double? lng;
  final String? locationLabel;
  final String body;
  final bool isLocating;
  final bool isSubmitting;

  static const maxBody = 200;

  bool get hasLocation => lat != null && lng != null;
  int get remaining => maxBody - body.runes.length;

  bool get isBodyValid {
    final n = body.trim().runes.length;
    return n >= 1 && n <= maxBody;
  }

  bool get canSubmit => hasLocation && isBodyValid && !isSubmitting;

  /// 入力済みか（キャンセル確認の要否）。
  bool get isDirty => body.trim().isNotEmpty;

  PinComposeState copyWith({
    double? lat,
    double? lng,
    String? locationLabel,
    String? body,
    bool? isLocating,
    bool? isSubmitting,
  }) =>
      PinComposeState(
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        locationLabel: locationLabel ?? this.locationLabel,
        body: body ?? this.body,
        isLocating: isLocating ?? this.isLocating,
        isSubmitting: isSubmitting ?? this.isSubmitting,
      );
}

/// PinComposeScreen のコントローラ（issue #37）。
class PinComposeController extends Notifier<PinComposeState> {
  @override
  PinComposeState build() => const PinComposeState();

  /// 起動時: 現在地を取得してミニ地図にセットし、場所ラベルを引く。
  Future<void> initialize() async {
    state = state.copyWith(isLocating: true);
    try {
      final pos = await ref.read(locationServiceProvider).currentPosition();
      // 先に位置を確定（地図表示はここで可能に）。
      state = state.copyWith(lat: pos.lat, lng: pos.lng, isLocating: false);
      // 場所ラベルは best-effort（geocoding は Web 非対応のことがある）。
      await _updateLabel(pos.lat, pos.lng);
    } catch (_) {
      state = state.copyWith(isLocating: false);
    }
  }

  /// ピンドラッグで座標を更新し、場所ラベルを引き直す。
  Future<void> updateLocation(double lat, double lng) async {
    state = state.copyWith(lat: lat, lng: lng);
    await _updateLabel(lat, lng);
  }

  /// 逆ジオコーディングでラベル更新（失敗しても無視）。
  Future<void> _updateLabel(double lat, double lng) async {
    try {
      final label =
          await ref.read(geocodingServiceProvider).reverseGeocode(lat, lng);
      if (label != null && label.isNotEmpty) {
        state = state.copyWith(locationLabel: label);
      }
    } catch (_) {
      // Web 等で逆ジオコーディング不可でも投稿は続行できる。
    }
  }

  void updateBody(String body) => state = state.copyWith(body: body);

  Future<PinComposeResult> submit() async {
    if (!state.canSubmit) return PinComposeResult.invalid;
    state = state.copyWith(isSubmitting: true);
    try {
      await ref.read(pinRepositoryProvider).create(
            body: state.body.trim(),
            lat: state.lat!,
            lng: state.lng!,
          );
      state = state.copyWith(isSubmitting: false);
      return PinComposeResult.success;
    } catch (_) {
      state = state.copyWith(isSubmitting: false);
      return PinComposeResult.error;
    }
  }
}

final pinComposeControllerProvider =
    NotifierProvider<PinComposeController, PinComposeState>(
  PinComposeController.new,
);
