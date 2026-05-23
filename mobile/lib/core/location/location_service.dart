import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// 緯度経度（google_maps の LatLng に依存せずコントローラ層で使える軽量型）。
class LatLngPoint {
  const LatLngPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is LatLngPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}

/// 位置情報の許可状態（plugin の enum を MVP 用に簡約したもの）。
enum LocationPermissionStatus { granted, denied, deniedForever }

/// 位置情報まわりの抽象。`geolocator` を直接参照せずテストで差し替える。
abstract class LocationService {
  /// 端末の位置情報サービス（GPS 等）が ON か。
  Future<bool> isServiceEnabled();

  /// 権限を確認し、未許可なら要求して最終状態を返す。
  Future<LocationPermissionStatus> ensurePermission();

  /// 現在地を取得する。
  Future<LatLngPoint> currentPosition();

  /// アプリの設定画面を開く（権限を恒久拒否された場合の導線）。
  Future<bool> openAppSettings();

  /// 端末の位置情報設定を開く（サービス OFF の場合の導線）。
  Future<bool> openLocationSettings();
}

/// `geolocator` を用いた本番実装。
class GeolocatorLocationService implements LocationService {
  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermissionStatus> ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse =>
        LocationPermissionStatus.granted,
      LocationPermission.deniedForever =>
        LocationPermissionStatus.deniedForever,
      _ => LocationPermissionStatus.denied,
    };
  }

  @override
  Future<LatLngPoint> currentPosition() async {
    final pos = await Geolocator.getCurrentPosition();
    return LatLngPoint(pos.latitude, pos.longitude);
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(),
);
