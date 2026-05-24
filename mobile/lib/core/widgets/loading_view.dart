import 'package:flutter/material.dart';

/// 読み込み中の共通表示。中央にインジケータ（任意でメッセージ）。
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
