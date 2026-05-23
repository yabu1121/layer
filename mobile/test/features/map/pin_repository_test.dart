import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/features/map/pin_repository.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('/api/pins/visible をパースして Pin リストを返す', () async {
    const body = '''
{"pins":[
  {"id":"p1","userId":"u1","body":"hello","lat":35.68,"lng":139.76,
   "createdAt":"2026-01-01T00:00:00Z",
   "author":{"id":"u1","userId":"taro","displayName":"たろう","icon":"🐱"}}
]}''';
    final dio = Dio()..httpClientAdapter = _StubAdapter(body);
    final repo = ApiPinRepository(dio);

    final pins = await repo.fetchVisible();

    expect(pins.length, 1);
    expect(pins.single.id, 'p1');
    expect(pins.single.ownerId, 'u1');
    expect(pins.single.lat, 35.68);
    expect(pins.single.author.displayName, 'たろう');
    expect(pins.single.isMine('u1'), isTrue);
    expect(pins.single.isMine('other'), isFalse);
  });

  test('pins が空でも空リストを返す', () async {
    final dio = Dio()..httpClientAdapter = _StubAdapter('{"pins":[]}');
    final pins = await ApiPinRepository(dio).fetchVisible();
    expect(pins, isEmpty);
  });
}
