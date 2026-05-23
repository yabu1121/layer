import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/models/pin.dart';

/// 「わかる」リアクションのリポジトリ（テストで差し替え可能なよう interface 化）。
abstract interface class ReactionRepository {
  /// 対象 Pin の共感者一覧を返す（GET /api/pins/:id/reactions）。
  Future<List<PinAuthor>> list(String pinId);

  /// 「わかる」を付ける（POST /api/pins/:id/reactions、kind は wakaru 固定）。
  Future<void> add(String pinId);

  /// 自分の「わかる」を取り消す（DELETE /api/pins/:id/reactions/me）。
  Future<void> removeMine(String pinId);
}

class ApiReactionRepository implements ReactionRepository {
  ApiReactionRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<PinAuthor>> list(String pinId) async {
    final res =
        await _dio.get<Map<String, dynamic>>('/api/pins/$pinId/reactions');
    final list = (res.data!['reactions'] as List?) ?? const [];
    return list
        .map((j) => PinAuthor.fromJson(
              ((j as Map)['user'] as Map).cast<String, dynamic>(),
            ))
        .toList();
  }

  @override
  Future<void> add(String pinId) async {
    await _dio.post<dynamic>('/api/pins/$pinId/reactions');
  }

  @override
  Future<void> removeMine(String pinId) async {
    await _dio.delete<dynamic>('/api/pins/$pinId/reactions/me');
  }
}

final reactionRepositoryProvider = Provider<ReactionRepository>(
  (ref) => ApiReactionRepository(ref.watch(apiClientProvider)),
);
