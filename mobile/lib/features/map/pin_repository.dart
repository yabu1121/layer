import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/models/pin.dart';

/// Pin 取得のリポジトリ（テストで差し替え可能なよう interface 化）。
abstract interface class PinRepository {
  /// 自分 + 友達の可視 Pin を取得する（GET /api/pins/visible）。
  Future<List<Pin>> fetchVisible();
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
}

final pinRepositoryProvider = Provider<PinRepository>(
  (ref) => ApiPinRepository(ref.watch(apiClientProvider)),
);
