import 'pin.dart';

/// Pin へのコメント（backend の comment item に対応、camelCase）。
class Comment {
  const Comment({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.author,
  });

  final String id;
  final String body;
  final DateTime? createdAt;
  final PinAuthor author; // 投稿者（JSON では user）

  /// 自分のコメントか（author.id と自分の UUID を比較）。
  bool isMine(String myUserId) => author.id == myUserId;

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
        id: json['id'] as String? ?? '',
        body: json['body'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        author: PinAuthor.fromJson(
          (json['user'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );
}
