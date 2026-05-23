import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/current_user.dart';
import '../../core/location/location_service.dart';
import '../../core/models/pin.dart';
import 'pin_repository.dart';

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
    this.pins = const [],
    this.myUserId,
  });

  final MapStatus status;

  /// 地図の中心（現在地）。ready のときのみ非 null。
  final LatLngPoint? center;

  /// 恒久拒否（再要求不可）。設定アプリ誘導の出し分けに使う。
  final bool permanentlyDenied;

  /// 自分 + 友達の可視 Pin（#34）。
  final List<Pin> pins;

  /// 自分の UUID（マーカー色の出し分け用）。
  final String? myUserId;

  MapState copyWith({
    MapStatus? status,
    LatLngPoint? center,
    List<Pin>? pins,
    String? myUserId,
  }) =>
      MapState(
        status: status ?? this.status,
        center: center ?? this.center,
        permanentlyDenied: permanentlyDenied,
        pins: pins ?? this.pins,
        myUserId: myUserId ?? this.myUserId,
      );
}

/// MapScreen のコントローラ（issue #33・#34）。
///
/// 位置情報サービス・権限を確認して現在地を供給し、可視 Pin を取得する。
class MapController extends Notifier<MapState> {
  @override
  MapState build() => const MapState(status: MapStatus.loading);

  /// 位置情報サービス／権限を確認 → 現在地取得 → 可視 Pin 取得。
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
    // 先に地図を表示し、Pin はベストエフォートで載せる。
    state = MapState(status: MapStatus.ready, center: pos);
    await _loadPins();
  }

  /// 可視 Pin と自分の UUID を取得して state に反映する。失敗しても地図は表示する。
  Future<void> _loadPins() async {
    try {
      final pins = await ref.read(pinRepositoryProvider).fetchVisible();
      String? myId;
      try {
        myId = (await ref.read(currentUserProvider.future)).id;
      } catch (_) {
        // 自分の情報が取れなくても Pin は表示する（色分けのみ諦める）。
      }
      state = state.copyWith(pins: pins, myUserId: myId);
    } catch (_) {
      // Pin 取得失敗時は地図のみ表示。
    }
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
