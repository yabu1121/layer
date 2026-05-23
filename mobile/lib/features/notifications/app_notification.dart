/// 通知1件（backend notificationItem に対応）。
/// payload は kind ごとに形が異なる（共通: displayName/icon）。
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.payload,
    this.readAt,
    this.createdAt,
  });

  final String id;
  final String kind; // discovery | reaction | friend_request | friend_accepted
  final Map<String, dynamic> payload;
  final DateTime? readAt;
  final DateTime? createdAt;

  String get displayName => payload['displayName'] as String? ?? '';
  String get icon => payload['icon'] as String? ?? '🔔';
  String? get pinId => payload['pinId'] as String?;
  String? get requestId => payload['requestId'] as String?;
  String? get body => payload['body'] as String?;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        readAt: DateTime.tryParse(json['readAt'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}
