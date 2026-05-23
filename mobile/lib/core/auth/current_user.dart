import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/user.dart';

/// 認証中ユーザー（GET /api/me）。自分の Pin 判定やプロフィール表示で再利用する。
final currentUserProvider = FutureProvider<User>((ref) async {
  final res =
      await ref.read(apiClientProvider).get<Map<String, dynamic>>('/api/me');
  return User.fromJson((res.data!['user'] as Map).cast<String, dynamic>());
});
