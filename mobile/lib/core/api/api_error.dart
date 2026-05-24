import 'package:dio/dio.dart';

/// 通信エラーをユーザー向けの日本語メッセージに変換する。
/// Web でも動くよう dart:io には依存せず DioException の型で判定する。
String friendlyErrorMessage(Object? error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'ネットに繋いでね（接続できませんでした）';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode ?? 0;
        if (code == 401) return 'ログインが必要です';
        if (code >= 500) return 'サーバーでエラーが発生しました';
        return '読み込みに失敗しました';
      default:
        return '読み込みに失敗しました';
    }
  }
  return '読み込みに失敗しました';
}

/// オフライン（接続不可・タイムアウト）由来のエラーか。
bool isOffline(Object? error) =>
    error is DioException &&
    (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout);
