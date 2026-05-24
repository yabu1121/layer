import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/features/pin_compose/image_upload_repository.dart';

/// presign には JSON を、R2 への PUT には 200 を返す偽アダプタ。
class _Adapter implements HttpClientAdapter {
  String? putContentType;
  bool putCalled = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('presign')) {
      return ResponseBody.fromString(
        '{"uploadUrl":"https://r2.example/put?sig=abc",'
        '"publicUrl":"https://cdn.example/pin-images/x.jpg"}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    // R2 への PUT。
    putCalled = true;
    putContentType = options.headers[Headers.contentTypeHeader]?.toString();
    return ResponseBody.fromString('', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('presign 取得 → R2 へ PUT → publicUrl を返す', () async {
    final adapter = _Adapter();
    final api = Dio()..httpClientAdapter = adapter;
    final r2 = Dio()..httpClientAdapter = adapter;
    final repo = ApiImageUploadRepository(api, r2Client: r2);

    final url = await repo.uploadPinImage(
      Uint8List.fromList([1, 2, 3]),
      'image/jpeg',
    );

    expect(url, 'https://cdn.example/pin-images/x.jpg');
    expect(adapter.putCalled, isTrue);
    expect(adapter.putContentType, contains('image/jpeg'));
  });
}
