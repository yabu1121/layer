/// Pin 投稿者の公開プロフィール（backend pinAuthor に対応、camelCase）。
class PinAuthor {
  const PinAuthor({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.icon,
  });

  final String id; // 投稿者の UUID（users.id）
  final String userId; // 表示用ハンドル
  final String displayName;
  final String icon;

  factory PinAuthor.fromJson(Map<String, dynamic> json) => PinAuthor(
        id: json['id'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
      );
}

/// 場所への投稿（backend createdPin に対応）。
class Pin {
  const Pin({
    required this.id,
    required this.ownerId,
    required this.body,
    required this.lat,
    required this.lng,
    required this.createdAt,
    required this.author,
    this.imageUrl,
  });

  final String id;
  final String ownerId; // 投稿者の UUID（JSON では userId）
  final String body;
  final double lat;
  final double lng;
  final DateTime? createdAt;
  final PinAuthor author;
  final String? imageUrl; // 任意。R2 上の画像 URL（US-B3）

  /// 自分の Pin か。author.id（= ownerId）と自分の UUID を比較する。
  bool isMine(String myUserId) => author.id == myUserId;

  factory Pin.fromJson(Map<String, dynamic> json) {
    final rawImage = json['imageUrl'] as String?;
    return Pin(
      id: json['id'] as String? ?? '',
      ownerId: json['userId'] as String? ?? '',
      body: json['body'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      author: PinAuthor.fromJson(
        (json['author'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      imageUrl: (rawImage != null && rawImage.isNotEmpty) ? rawImage : null,
    );
  }
}
