import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:layer/core/auth/current_user.dart';
import 'package:layer/core/location/location_service.dart';
import 'package:layer/core/models/pin.dart';
import 'package:layer/core/models/user.dart';
import 'package:layer/features/map/map_screen.dart';
import 'package:layer/features/map/pin_repository.dart';
import 'package:layer/features/notifications/app_notification.dart';
import 'package:layer/features/notifications/notification_repository.dart';

class _FakePinRepository implements PinRepository {
  _FakePinRepository(this.pins);
  final List<Pin> pins;
  @override
  Future<List<Pin>> fetchVisible({bool friendsOnly = false}) async => pins;
  @override
  Future<void> delete(String id) async {}
  @override
  Future<Pin> getById(String id) async => throw UnimplementedError();
  @override
  Future<List<Pin>> getNearby(String id) async => const [];
  @override
  Future<Pin> create({
    required String body,
    required double lat,
    required double lng,
    String? imageUrl,
  }) async =>
      throw UnimplementedError();
}

class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository([this.items = const []]);
  final List<AppNotification> items;
  @override
  Future<int> fetchUnreadCount() async => 0;
  @override
  Future<List<AppNotification>> list({int limit = 50}) async => items;
  @override
  Future<void> markAllRead() async {}
}

class _FakeLocationService implements LocationService {
  _FakeLocationService({
    this.serviceEnabled = true,
    this.permission = LocationPermissionStatus.granted,
  });

  final bool serviceEnabled;
  final LocationPermissionStatus permission;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermissionStatus> ensurePermission() async => permission;

  @override
  Future<LatLngPoint> currentPosition() async => const LatLngPoint(35.0, 139.0);

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

Widget _app(
  _FakeLocationService loc, {
  List<AppNotification> notifications = const [],
}) =>
    ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(loc),
        pinRepositoryProvider.overrideWithValue(_FakePinRepository(const [])),
        notificationRepositoryProvider
            .overrideWithValue(_FakeNotificationRepository(notifications)),
        currentUserProvider.overrideWith(
          (ref) async => const User(
            id: 'me',
            userId: 'me',
            displayName: 'Me',
            icon: '😀',
          ),
        ),
      ],
      child: const MaterialApp(home: MapScreen()),
    );

void main() {
  testWidgets('サービス OFF → 案内と設定リンク', (tester) async {
    await tester.pumpWidget(_app(_FakeLocationService(serviceEnabled: false)));
    await tester.pumpAndSettle();

    expect(find.text('位置情報サービスがオフです'), findsOneWidget);
    expect(find.text('位置情報設定を開く'), findsOneWidget);
  });

  testWidgets('権限拒否 → 許可を促す案内', (tester) async {
    await tester.pumpWidget(
      _app(_FakeLocationService(permission: LocationPermissionStatus.denied)),
    );
    await tester.pumpAndSettle();

    expect(find.text('位置情報の許可が必要です'), findsOneWidget);
  });

  testWidgets('許可済み → 地図と現在地ボタンを表示', (tester) async {
    await tester.pumpWidget(_app(_FakeLocationService()));
    await tester.pumpAndSettle();

    expect(find.byType(GoogleMap), findsOneWidget);
    expect(find.byTooltip('現在地'), findsOneWidget);
  });

  testWidgets('凡例: タップで色の意味を開閉できる', (tester) async {
    await tester.pumpWidget(_app(_FakeLocationService()));
    await tester.pumpAndSettle();

    expect(find.text('凡例'), findsOneWidget);
    expect(find.text('友達の現在地'), findsNothing); // 折りたたみ時は非表示

    await tester.tap(find.text('凡例'));
    await tester.pumpAndSettle();
    expect(find.text('自分'), findsOneWidget);
    expect(find.text('友達の現在地'), findsOneWidget);
  });

  testWidgets('未読通知があると起動バナーを表示し、閉じられる', (tester) async {
    final notif = AppNotification(
      id: 'n1',
      kind: 'discovery',
      payload: const {'displayName': 'アヤ', 'icon': '🌸', 'pinId': 'p1'},
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(
      _app(_FakeLocationService(), notifications: [notif]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('同じ場所に Pin を立てました'), findsOneWidget);

    await tester.tap(find.byTooltip('閉じる'));
    await tester.pumpAndSettle();
    expect(find.textContaining('同じ場所に Pin を立てました'), findsNothing);
  });
}
