import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/auth/current_user.dart';
import 'package:layer/core/models/pin.dart';
import 'package:layer/core/models/user.dart';
import 'package:layer/features/friends/friend_repository.dart';
import 'package:layer/features/friends/friends_screen.dart';

class _FakeFriendRepo implements FriendRepository {
  _FakeFriendRepo({this.found, this.incoming = const []});
  final PinAuthor? found;
  final List<IncomingRequest> incoming;
  SendRequestResult result = SendRequestResult.sent;

  @override
  Future<PinAuthor?> searchUser(String userId) async => found;
  @override
  Future<List<PinAuthor>> listFriends() async => const [];
  @override
  Future<SendRequestResult> sendRequest(String receiverId) async => result;
  @override
  Future<List<IncomingRequest>> listIncoming() async => incoming;
  @override
  Future<void> accept(String requestId) async {}
  @override
  Future<void> reject(String requestId) async {}
}

Widget _app({PinAuthor? found, List<IncomingRequest> incoming = const []}) =>
    ProviderScope(
      overrides: [
        friendRepositoryProvider
            .overrideWithValue(_FakeFriendRepo(found: found, incoming: incoming)),
        currentUserProvider.overrideWith(
          (ref) async => const User(
            id: 'me',
            userId: 'me',
            displayName: 'Me',
            icon: '😀',
          ),
        ),
      ],
      child: const MaterialApp(home: FriendsScreen()),
    );

void main() {
  testWidgets('入力 → デバウンス後に結果と申請ボタン、タップで申請中', (tester) async {
    const user =
        PinAuthor(id: 'u1', userId: 'aya', displayName: 'アヤ', icon: '🌸');
    await tester.pumpWidget(_app(found: user));

    await tester.enterText(find.byType(TextField), 'aya');
    // 500ms デバウンス + 検索完了を待つ。
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('アヤ'), findsOneWidget);
    expect(find.text('友達申請'), findsOneWidget);

    await tester.tap(find.text('友達申請'));
    await tester.pumpAndSettle();
    expect(find.text('申請中'), findsOneWidget);
  });

  testWidgets('不在で「見つかりませんでした」', (tester) async {
    await tester.pumpWidget(_app());
    await tester.enterText(find.byType(TextField), 'nobody');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('ユーザーが見つかりませんでした'), findsOneWidget);
  });

  testWidgets('受信申請が一覧表示され、承認で消える', (tester) async {
    const requester =
        PinAuthor(id: 'a', userId: 'aya', displayName: 'アヤ', icon: '🌸');
    await tester.pumpWidget(
      _app(incoming: const [IncomingRequest(id: 'r1', requester: requester)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('申請中（1）'), findsOneWidget);
    expect(find.text('アヤ'), findsOneWidget);
    expect(find.text('承認'), findsOneWidget);

    await tester.tap(find.text('承認'));
    await tester.pumpAndSettle();
    expect(find.text('申請中（1）'), findsNothing); // セクション消える
  });
}
