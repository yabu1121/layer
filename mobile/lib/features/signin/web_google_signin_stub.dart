import 'package:flutter/widgets.dart';

/// 非 Web では使わない（条件付き import のスタブ）。
Widget buildWebGoogleSignInButton({
  required void Function(String idToken) onIdToken,
}) =>
    const SizedBox.shrink();
