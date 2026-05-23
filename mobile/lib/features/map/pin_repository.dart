import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/models/pin.dart';

/// Pin 取得・投稿のリポジトリ（テストで差し替え可能なよう interface 化）。
abstract interface class PinRepository {
  /// 自分 + 友達の可視 Pin を取得する（GET /api/pins/visible）。
  Future<List<Pin>> fetchVisible();

  /// Pin を投稿する（POST /api/pins）。作成された Pin を返す。
  Future<Pin> create({
    required String body,
    required double lat,
    required double lng,
  });

  /// Pin 単体を取得する（GET /api/pins/:id）。
  Future<Pin> getById(String id);

  /// 同じ場所の近傍 Pin を取得する（GET /api/pins/:id/nearby）。
  Future<List<Pin>> getNearby(String id);
}

class ApiPinRepository implements PinRepository {
  ApiPinRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<Pin>> fetchVisible() async {
    final res =
        await _dio.get<Map<String, dynamic>>('/api/pins/visible');
    final list = (res.data!['pins'] as List?) ?? const [];
    return list
        .map((j) => Pin.fromJson((j as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<Pin> create({
    required String body,
    required double lat,
    required double lng,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/pins',
      data: {'body': body, 'lat': lat, 'lng': lng},
    );
    return Pin.fromJson((res.data!['pin'] as Map).cast<String, dynamic>());
  }

  @override
  Future<Pin> getById(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/api/pins/$id');
    return Pin.fromJson((res.data!['pin'] as Map).cast<String, dynamic>());
  }

  @override
  Future<List<Pin>> getNearby(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/api/pins/$id/nearby');
    final list = (res.data!['pins'] as List?) ?? const [];
    return list
        .map((j) => Pin.fromJson((j as Map).cast<String, dynamic>()))
        .toList();
  }
}

final pinRepositoryProvider = Provider<PinRepository>(
  (ref) => ApiPinRepository(ref.watch(apiClientProvider)),
);
