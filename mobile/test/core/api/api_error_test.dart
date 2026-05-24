import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/api/api_error.dart';

DioException _dio(DioExceptionType type, {int? status}) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: type,
      response: status == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: '/x'),
              statusCode: status,
            ),
    );

void main() {
  test('接続エラーはオフライン文言', () {
    expect(friendlyErrorMessage(_dio(DioExceptionType.connectionError)),
        contains('ネットに繋いでね'));
    expect(friendlyErrorMessage(_dio(DioExceptionType.connectionTimeout)),
        contains('ネットに繋いでね'));
    expect(isOffline(_dio(DioExceptionType.connectionError)), isTrue);
  });

  test('401 はログイン要求', () {
    expect(
      friendlyErrorMessage(_dio(DioExceptionType.badResponse, status: 401)),
      'ログインが必要です',
    );
  });

  test('5xx はサーバーエラー', () {
    expect(
      friendlyErrorMessage(_dio(DioExceptionType.badResponse, status: 503)),
      contains('サーバー'),
    );
  });

  test('その他の bad response は汎用メッセージ', () {
    expect(
      friendlyErrorMessage(_dio(DioExceptionType.badResponse, status: 404)),
      '読み込みに失敗しました',
    );
    expect(isOffline(_dio(DioExceptionType.badResponse, status: 404)), isFalse);
  });

  test('非 Dio エラーは汎用メッセージ', () {
    expect(friendlyErrorMessage(Exception('boom')), '読み込みに失敗しました');
    expect(isOffline(Exception('boom')), isFalse);
  });
}
