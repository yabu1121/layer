import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

/// 通知 API のリポジトリ（テストで差し替え可能なよう interface 化）。
abstract interface class NotificationRepository {
  /// 未読通知数を取得する（GET /api/notifications/unread-count）。
  Future<int> fetchUnreadCount();
}

class ApiNotificationRepository implements NotificationRepository {
  ApiNotificationRepository(this._dio);

  final Dio _dio;

  @override
  Future<int> fetchUnreadCount() async {
    final res = await _dio
        .get<Map<String, dynamic>>('/api/notifications/unread-count');
    return (res.data?['count'] as num?)?.toInt() ?? 0;
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => ApiNotificationRepository(ref.watch(apiClientProvider)),
);
