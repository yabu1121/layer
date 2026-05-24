import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// 選択された画像（バイト列 + content-type）。
class PickedImage {
  const PickedImage({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

/// 画像選択を抽象化（テストで差し替え可能なよう interface 化）。
abstract interface class ImagePickerService {
  /// ギャラリーから画像を1枚選ぶ。キャンセルで null。
  Future<PickedImage?> pick();
}

class ImagePickerServiceImpl implements ImagePickerService {
  final _picker = ImagePicker();

  @override
  Future<PickedImage?> pick() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    return PickedImage(bytes: bytes, contentType: _contentType(x.name));
  }

  String _contentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

final imagePickerServiceProvider =
    Provider<ImagePickerService>((ref) => ImagePickerServiceImpl());
