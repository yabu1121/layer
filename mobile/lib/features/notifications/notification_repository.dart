import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import 'app_notification.dart';

/// 通知 API のリポジトリ（テストで差し替え可能なよう interface 化）。
abstract interface class NotificationRepository {
  /// 未読通知数を取得する（GET /api/notifications/unread-count）。
  Future<int> fetchUnreadCount();

  /// 通知一覧を新しい順で取得する（GET /api/notifications）。
  Future<List<AppNotification>> list({int limit});

  /// すべて既読化する（POST /api/notifications/read-all）。
  Future<void> markAllRead();
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

  @override
  Future<List<AppNotification>> list({int limit = 50}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/notifications',
      queryParameters: {'limit': limit},
    );
    final list = (res.data!['notifications'] as List?) ?? const [];
    return list
        .map((j) => AppNotification.fromJson((j as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> markAllRead() async {
    await _dio.post<dynamic>('/api/notifications/read-all');
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => ApiNotificationRepository(ref.watch(apiClientProvider)),
);
