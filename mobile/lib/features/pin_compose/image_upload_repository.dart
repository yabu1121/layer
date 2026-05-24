import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

/// 画像を R2 にアップロードするリポジトリ（US-B3）。
/// presign を取得 → R2 へ直接 PUT → 公開 URL を返す。
abstract interface class ImageUploadRepository {
  Future<String> uploadPinImage(Uint8List bytes, String contentType);
}

class ApiImageUploadRepository implements ImageUploadRepository {
  /// [r2Client] は R2 への PUT 用（baseUrl・認証を持たない素の Dio）。
  /// presigned URL に署名が含まれるため Authorization を足してはいけない。
  ApiImageUploadRepository(this._dio, {Dio? r2Client}) : _r2 = r2Client ?? Dio();

  final Dio _dio;
  final Dio _r2;

  @override
  Future<String> uploadPinImage(Uint8List bytes, String contentType) async {
    final presign = await _dio.post<Map<String, dynamic>>(
      '/api/uploads/pin-image/presign',
      data: {'contentType': contentType},
    );
    final uploadUrl = presign.data!['uploadUrl'] as String;
    final publicUrl = presign.data!['publicUrl'] as String;

    await _r2.put<void>(
      uploadUrl,
      data: bytes,
      options: Options(headers: {Headers.contentTypeHeader: contentType}),
    );
    return publicUrl;
  }
}

final imageUploadRepositoryProvider = Provider<ImageUploadRepository>(
  (ref) => ApiImageUploadRepository(ref.watch(apiClientProvider)),
);
