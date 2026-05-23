import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/models/pin.dart';

/// 友達申請送信の結果。
enum SendRequestResult { sent, alreadyRequested, alreadyFriends, error }

/// 受信した友達申請（申請 ID + 申請者）。
class IncomingRequest {
  const IncomingRequest({required this.id, required this.requester});

  final String id;
  final PinAuthor requester;

  factory IncomingRequest.fromJson(Map<String, dynamic> json) =>
      IncomingRequest(
        id: json['id'] as String? ?? '',
        requester: PinAuthor.fromJson(
          ((json['requester'] as Map?)?.cast<String, dynamic>()) ?? const {},
        ),
      );
}

/// 友達まわりのリポジトリ（テストで差し替え可能なよう interface 化）。
/// 共有ユーザー型として [PinAuthor]（id/userId/displayName/icon）を流用する。
abstract interface class FriendRepository {
  /// user_id 完全一致でユーザーを検索する（見つからなければ null）。
  Future<PinAuthor?> searchUser(String userId);

  /// accepted な友達一覧を返す（GET /api/friends）。
  Future<List<PinAuthor>> listFriends();

  /// 友達申請を送る（POST /api/friends/requests）。
  Future<SendRequestResult> sendRequest(String receiverId);

  /// 受信した友達申請一覧（GET /api/friends/requests/incoming）。
  Future<List<IncomingRequest>> listIncoming();

  /// 申請を承認する（POST /api/friends/requests/:id/accept）。
  Future<void> accept(String requestId);

  /// 申請を拒否する（POST /api/friends/requests/:id/reject）。
  Future<void> reject(String requestId);
}

class ApiFriendRepository implements FriendRepository {
  ApiFriendRepository(this._dio);

  final Dio _dio;

  @override
  Future<PinAuthor?> searchUser(String userId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/users/search',
        queryParameters: {'user_id': userId},
      );
      return PinAuthor.fromJson(
        (res.data!['user'] as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<PinAuthor>> listFriends() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/friends');
    final list = (res.data!['friends'] as List?) ?? const [];
    return list
        .map((j) => PinAuthor.fromJson((j as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<SendRequestResult> sendRequest(String receiverId) async {
    try {
      await _dio.post<dynamic>(
        '/api/friends/requests',
        data: {'receiver_id': receiverId},
      );
      return SendRequestResult.sent;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final data = e.response?.data;
        final err = data is Map ? data['error'] : null;
        return err == 'already_friends'
            ? SendRequestResult.alreadyFriends
            : SendRequestResult.alreadyRequested;
      }
      return SendRequestResult.error;
    }
  }

  @override
  Future<List<IncomingRequest>> listIncoming() async {
    final res = await _dio
        .get<Map<String, dynamic>>('/api/friends/requests/incoming');
    final list = (res.data!['requests'] as List?) ?? const [];
    return list
        .map((j) => IncomingRequest.fromJson((j as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> accept(String requestId) async {
    await _dio.post<dynamic>('/api/friends/requests/$requestId/accept');
  }

  @override
  Future<void> reject(String requestId) async {
    await _dio.post<dynamic>('/api/friends/requests/$requestId/reject');
  }
}

final friendRepositoryProvider = Provider<FriendRepository>(
  (ref) => ApiFriendRepository(ref.watch(apiClientProvider)),
);
