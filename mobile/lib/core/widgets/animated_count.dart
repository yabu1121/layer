import 'package:flutter/material.dart';

/// 数値を 0（初回）または直前の値から目標値までカウントアップ表示する。
/// 値が変わると差分をアニメーションする（TweenAnimationBuilder の挙動）。
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 500),
  });

  final int value;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, v, _) => Text('$v', style: style),
    );
  }
}
