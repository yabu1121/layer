import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location/location_service.dart';

/// MapScreen の表示状態。
enum MapStatus {
  loading, // 位置情報の取得中
  ready, // 現在地を取得して地図表示可能
  permissionDenied, // 権限拒否
  serviceDisabled, // 位置情報サービス OFF
}

class MapState {
  const MapState({
    required this.status,
    this.center,
    this.permanentlyDenied = false,
  });

  final MapStatus status;

  /// 地図の中心（現在地）。ready のときのみ非 null。
  final LatLngPoint? center;

  /// 恒久拒否（再要求不可）。設定アプリ誘導の出し分けに使う。
  final bool permanentlyDenied;

  MapState copyWith({MapStatus? status, LatLngPoint? center}) => MapState(
        status: status ?? this.status,
        center: center ?? this.center,
        permanentlyDenied: permanentlyDenied,
      );
}

/// MapScreen のコントローラ（issue #33）。
///
/// 位置情報サービス・権限を確認し、現在地を初期カメラ位置として供給する。
/// Pin 描画やクラスタは本 issue の範囲外。
class MapController extends Notifier<MapState> {
  @override
  MapState build() => const MapState(status: MapStatus.loading);

  /// 位置情報サービス／権限を確認して現在地を取得する。
  /// 画面の initState および「再試行」から呼ぶ。
  Future<void> load() async {
    state = const MapState(status: MapStatus.loading);
    final location = ref.read(locationServiceProvider);

    if (!await location.isServiceEnabled()) {
      state = const MapState(status: MapStatus.serviceDisabled);
      return;
    }

    final permission = await location.ensurePermission();
    if (permission != LocationPermissionStatus.granted) {
      state = MapState(
        status: MapStatus.permissionDenied,
        permanentlyDenied:
            permission == LocationPermissionStatus.deniedForever,
      );
      return;
    }

    final pos = await location.currentPosition();
    state = MapState(status: MapStatus.ready, center: pos);
  }

  /// 現在地ボタン: 位置を取り直して center を更新する（カメラ移動は画面側）。
  Future<void> recenter() async {
    final location = ref.read(locationServiceProvider);
    try {
      final pos = await location.currentPosition();
      state = state.copyWith(center: pos);
    } catch (_) {
      // 取得失敗時は現状維持（地図は前回位置のまま）。
    }
  }
}

final mapControllerProvider =
    NotifierProvider<MapController, MapState>(MapController.new);
