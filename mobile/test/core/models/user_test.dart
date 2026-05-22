import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/models/user.dart';

void main() {
  test('camelCase の JSON をパースする', () {
    final user = User.fromJson({
      'id': 'uuid-1',
      'userId': 'user_abc',
      'displayName': 'たろう',
      'icon': '🐱',
    });
    expect(user.id, 'uuid-1');
    expect(user.userId, 'user_abc');
    expect(user.displayName, 'たろう');
    expect(user.icon, '🐱');
    expect(user.hasProfile, isTrue);
  });

  test('displayName が空なら hasProfile は false', () {
    final user = User.fromJson({
      'id': 'uuid-1',
      'userId': 'user_abc',
      'displayName': '',
      'icon': '',
    });
    expect(user.hasProfile, isFalse);
  });

  test('欠損フィールドは空文字にフォールバックする', () {
    final user = User.fromJson({'id': 'uuid-1'});
    expect(user.userId, '');
    expect(user.displayName, '');
    expect(user.hasProfile, isFalse);
  });
}
