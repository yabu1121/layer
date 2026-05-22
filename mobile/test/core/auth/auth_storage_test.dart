import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/auth/auth_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ID トークンを保存・読み出し・削除できる', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = AuthStorage(prefs);

    expect(storage.readIdToken(), isNull);

    await storage.saveIdToken('token-abc');
    expect(storage.readIdToken(), 'token-abc');

    await storage.clear();
    expect(storage.readIdToken(), isNull);
  });
}
