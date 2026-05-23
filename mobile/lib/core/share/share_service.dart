import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// OS 共有シートの抽象（テストで差し替え可能にする）。
abstract interface class ShareService {
  Future<void> share(String text);
}

class PlusShareService implements ShareService {
  @override
  Future<void> share(String text) => Share.share(text);
}

final shareServiceProvider =
    Provider<ShareService>((ref) => PlusShareService());
