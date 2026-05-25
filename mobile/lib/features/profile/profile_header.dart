import 'package:flutter/material.dart';

import '../../core/widgets/animated_count.dart';

/// 自分/他人プロフィールで共用するヘッダ（アイコン・表示名・@ハンドル・投稿数）。
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.icon,
    required this.displayName,
    required this.userId,
    this.postCount,
  });

  final String icon;
  final String displayName;
  final String userId;

  /// 投稿数（未取得なら null で非表示）。
  final int? postCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 56)),
        const SizedBox(height: 8),
        Text(displayName, style: theme.textTheme.titleLarge),
        Text('@$userId', style: theme.textTheme.bodyMedium),
        if (postCount != null) ...[
          const SizedBox(height: 12),
          _Stat(label: '投稿', value: postCount!),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        AnimatedCount(
          value: value,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
