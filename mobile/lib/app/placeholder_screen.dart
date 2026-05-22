import 'package:flutter/material.dart';

/// 後続 issue（#30〜#44）で各画面を実装するまでの仮表示。
/// ルート名を AppBar と本文に出し、遷移確認に使えるようにする。
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: Center(child: Text('$label（準備中）')),
    );
  }
}
