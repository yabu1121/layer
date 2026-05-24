import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/location/location_service.dart';

/// 他ユーザーの現在地（点表示）の取得と、自分の現在地の更新。
abstract interface class UserLocationRepository {
  /// 自分の現在地を更新する（POST /api/me/location）。
  Future<void> updateMine(double lat, double lng);

  /// 自分以外の現在地一覧を取得する（GET /api/locations）。
  Future<List<LatLngPoint>> fetchOthers();
}

class ApiUserLocationRepository implements UserLocationRepository {
  ApiUserLocationRepository(this._dio);

  final Dio _dio;

  @override
  Future<void> updateMine(double lat, double lng) async {
    await _dio.post<dynamic>('/api/me/location', data: {'lat': lat, 'lng': lng});
  }

  @override
  Future<List<LatLngPoint>> fetchOthers() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/locations');
    final list = (res.data!['locations'] as List?) ?? const [];
    return list.map((j) {
      final m = (j as Map).cast<String, dynamic>();
      return LatLngPoint(
        (m['lat'] as num).toDouble(),
        (m['lng'] as num).toDouble(),
      );
    }).toList();
  }
}

final userLocationRepositoryProvider = Provider<UserLocationRepository>(
  (ref) => ApiUserLocationRepository(ref.watch(apiClientProvider)),
);
