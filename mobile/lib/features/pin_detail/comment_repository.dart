import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/models/comment.dart';

/// Pin コメントのリポジトリ（テストで差し替え可能なよう interface 化）。
abstract interface class CommentRepository {
  /// 対象 Pin のコメント一覧（GET /api/pins/:id/comments、古い順）。
  Future<List<Comment>> list(String pinId);

  /// コメントを投稿する（POST /api/pins/:id/comments）。作成された 1 件を返す。
  Future<Comment> create(String pinId, String body);

  /// 自分のコメントを削除する（DELETE /api/pins/:id/comments/:commentId）。
  Future<void> delete(String pinId, String commentId);
}

class ApiCommentRepository implements CommentRepository {
  ApiCommentRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<Comment>> list(String pinId) async {
    final res =
        await _dio.get<Map<String, dynamic>>('/api/pins/$pinId/comments');
    final list = (res.data!['comments'] as List?) ?? const [];
    return list
        .map((j) => Comment.fromJson((j as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<Comment> create(String pinId, String body) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/pins/$pinId/comments',
      data: {'body': body},
    );
    return Comment.fromJson(
      ((res.data!['comment']) as Map).cast<String, dynamic>(),
    );
  }

  @override
  Future<void> delete(String pinId, String commentId) async {
    await _dio.delete<dynamic>('/api/pins/$pinId/comments/$commentId');
  }
}

final commentRepositoryProvider = Provider<CommentRepository>(
  (ref) => ApiCommentRepository(ref.watch(apiClientProvider)),
);
