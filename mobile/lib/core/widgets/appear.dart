import 'package:flutter/material.dart';

/// 子を初回表示時にフェード＋わずかなスライドで登場させる薄いラッパ。
/// [index] に応じて開始を少し遅らせ、リストでスタッガード表示にする。
/// 遅延は Timer ではなく単一アニメーションの Interval で表現する
/// （テストで保留タイマーを残さないため）。
class Appear extends StatefulWidget {
  const Appear({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    final steps = widget.index.clamp(0, 6);
    final totalMs = 220 + 30 * steps;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );
    // 先頭の (30*steps)/total を「待ち」に充て、残りでフェードイン。
    final start = (30 * steps) / totalMs;
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1.0, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(_fade);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
