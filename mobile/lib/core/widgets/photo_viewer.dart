import 'package:flutter/material.dart';

/// 画像の全画面ビューア（黒背景・ピンチズーム・タップ/×で閉じる）。
/// [heroTag] を与えると一覧側の画像と Hero トランジションする。
class PhotoViewer extends StatelessWidget {
  const PhotoViewer({super.key, required this.url, this.heroTag});

  final String url;
  final Object? heroTag;

  /// 全画面ビューアを開く（Hero つき）。
  static Future<void> open(BuildContext context, String url) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PhotoViewer(url: url, heroTag: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget image = Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) =>
          const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 64),
    );
    if (heroTag != null) image = Hero(tag: heroTag!, child: image);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(child: image),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: '閉じる',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
