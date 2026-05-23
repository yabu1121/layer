import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';

/// 座標 → 場所名（逆ジオコーディング）の抽象。`geocoding` を直接参照せず
/// テストで差し替えられるようにする。
abstract interface class GeocodingService {
  /// 緯度経度から人間可読な場所ラベルを返す（取得できなければ null）。
  Future<String?> reverseGeocode(double lat, double lng);
}

class GeoGeocodingService implements GeocodingService {
  @override
  Future<String?> reverseGeocode(double lat, double lng) async {
    final placemarks = await placemarkFromCoordinates(lat, lng);
    if (placemarks.isEmpty) return null;
    final p = placemarks.first;
    // 日本の住所を想定し、市区町村〜番地レベルを連結する。
    final parts = [
      p.administrativeArea,
      p.locality,
      p.subLocality,
      p.thoroughfare,
    ].where((s) => s != null && s.isNotEmpty).toList();
    if (parts.isEmpty) {
      return (p.name?.isNotEmpty ?? false) ? p.name : null;
    }
    return parts.join('');
  }
}

final geocodingServiceProvider = Provider<GeocodingService>(
  (ref) => GeoGeocodingService(),
);
