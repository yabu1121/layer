import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location/geocoding_service.dart';
import '../../core/models/pin.dart';
import '../map/pin_repository.dart';

enum PinDetailStatus { loading, ready, error }

class PinDetailState {
  const PinDetailState({
    this.status = PinDetailStatus.loading,
    this.mainPin,
    this.nearby = const [],
    this.locationLabel,
  });

  final PinDetailStatus status;
  final Pin? mainPin;
  final List<Pin> nearby;
  final String? locationLabel;

  /// 同じ場所の Pin 総数（メイン + 近傍）。
  int get totalCount => (mainPin == null ? 0 : 1) + nearby.length;
}

/// PinDetailScreen のコントローラ（issue #38）。
///
/// メイン Pin と同じ場所の近傍 Pin、場所ラベルを取得する。
/// 近傍 Pin タップ時は [selectPin] で同じ画面の内容を差し替える。
class PinDetailController extends Notifier<PinDetailState> {
  @override
  PinDetailState build() => const PinDetailState();

  Future<void> load(String pinId) async {
    state = const PinDetailState();
    try {
      final repo = ref.read(pinRepositoryProvider);
      final pin = await repo.getById(pinId);
      final nearby = await repo.getNearby(pinId);
      final label = await ref
          .read(geocodingServiceProvider)
          .reverseGeocode(pin.lat, pin.lng);
      state = PinDetailState(
        status: PinDetailStatus.ready,
        mainPin: pin,
        nearby: nearby,
        locationLabel: label,
      );
    } catch (_) {
      state = const PinDetailState(status: PinDetailStatus.error);
    }
  }

  /// 近傍 Pin を選び直して内容を差し替える。
  Future<void> selectPin(String pinId) => load(pinId);
}

final pinDetailControllerProvider =
    NotifierProvider<PinDetailController, PinDetailState>(
  PinDetailController.new,
);
