/// 認証ユーザー。バックエンドの `model.User`（JSON は camelCase）に対応する。
///
/// 参照: backend/internal/model/model.go の User（json:"userId" など）。
class User {
  const User({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.icon,
  });

  final String id;
  final String userId;
  final String displayName;
  final String icon;

  /// 表示名が設定済みか。オンボーディング完了の判定に使う。
  bool get hasProfile => displayName.isNotEmpty;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
    );
  }
}
