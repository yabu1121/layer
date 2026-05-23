import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/features/pin_detail/reaction_repository.dart';

class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this.body);

  final String body;
  String? method;
  String? path;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    method = options.method;
    path = options.path;
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
  test('list: reactions[].user を PinAuthor にパースする', () async {
    const body = '''
{"reactions":[
  {"id":"r1","user":{"id":"u1","userId":"taro","displayName":"たろう","icon":"🐱"}},
  {"id":"r2","user":{"id":"u2","userId":"hana","displayName":"はな","icon":"🌸"}}
]}''';
    final dio = Dio()..httpClientAdapter = _CapturingAdapter(body);
    final reactors = await ApiReactionRepository(dio).list('p1');
    expect(reactors.length, 2);
    expect(reactors.first.id, 'u1');
    expect(reactors.first.displayName, 'たろう');
  });

  test('add: POST /api/pins/:id/reactions', () async {
    final adapter = _CapturingAdapter('{}');
    await ApiReactionRepository(Dio()..httpClientAdapter = adapter).add('p1');
    expect(adapter.method, 'POST');
    expect(adapter.path, '/api/pins/p1/reactions');
  });

  test('removeMine: DELETE /api/pins/:id/reactions/me', () async {
    final adapter = _CapturingAdapter('{}');
    await ApiReactionRepository(Dio()..httpClientAdapter = adapter)
        .removeMine('p1');
    expect(adapter.method, 'DELETE');
    expect(adapter.path, '/api/pins/p1/reactions/me');
  });
}
