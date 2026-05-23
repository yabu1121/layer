import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/app/router.dart';
import 'package:layer/core/auth/auth_storage.dart';
import 'package:layer/core/auth/current_user.dart';
import 'package:layer/core/location/geocoding_service.dart';
import 'package:layer/core/location/location_service.dart';
import 'package:layer/core/models/pin.dart';
import 'package:layer/core/models/user.dart';
import 'package:layer/features/map/pin_repository.dart';
import 'package:layer/features/notifications/notification_repository.dart';
import 'package:layer/features/pin_detail/reaction_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// /map（MapScreen）が実機の Geolocator を呼ばないようにするスタブ。
/// サービス OFF を返し、決まった案内文を出させる。
class _StubLocationService implements LocationService {
  @override
  Future<bool> isServiceEnabled() async => false;
  @override
  Future<LocationPermissionStatus> ensurePermission() async =>
      LocationPermissionStatus.denied;
  @override
  Future<LatLngPoint> currentPosition() async => const LatLngPoint(0, 0);
  @override
  Future<bool> openAppSettings() async => true;
  @override
  Future<bool> openLocationSettings() async => true;
}

class _StubNotificationRepository implements NotificationRepository {
  @override
  Future<int> fetchUnreadCount() async => 0;
}

class _StubGeocoding implements GeocodingService {
  @override
  Future<String?> reverseGeocode(double lat, double lng) async => '東京都';
}

class _StubPinRepository implements PinRepository {
  @override
  Future<Pin> getById(String id) async => Pin(
        id: id,
        ownerId: 'o',
        body: 'b',
        lat: 0,
        lng: 0,
        createdAt: DateTime(2026),
        author: const PinAuthor(id: 'o', userId: 'h', displayName: 'n', icon: '🐱'),
      );
  @override
  Future<List<Pin>> getNearby(String id) async => const [];
  @override
  Future<List<Pin>> fetchVisible() async => const [];
  @override
  Future<Pin> create({
    required String body,
    required double lat,
    required double lng,
  }) async =>
      throw UnimplementedError();
}

class _StubReactionRepository implements ReactionRepository {
  @override
  Future<List<PinAuthor>> list(String pinId) async => const [];
  @override
  Future<void> add(String pinId) async {}
  @override
  Future<void> removeMine(String pinId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('各ルートに遷移して Placeholder を表示する', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = AuthStorage(prefs); // トークン無し

    final container = ProviderContainer(
      overrides: [
        authStorageProvider.overrideWithValue(storage),
        locationServiceProvider.overrideWithValue(_StubLocationService()),
        notificationRepositoryProvider
            .overrideWithValue(_StubNotificationRepository()),
        geocodingServiceProvider.overrideWithValue(_StubGeocoding()),
        pinRepositoryProvider.overrideWithValue(_StubPinRepository()),
        reactionRepositoryProvider
            .overrideWithValue(_StubReactionRepository()),
        currentUserProvider.overrideWith(
          (ref) async => const User(
            id: 'me',
            userId: 'me',
            displayName: 'Me',
            icon: '😀',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // 初期ルート '/' の SplashScreen はトークン無しのため /signin（SignInScreen）へ自動遷移する。
    expect(find.text('Google でサインイン'), findsOneWidget);

    // /map は MapScreen。スタブはサービス OFF を返すため案内文が出る。
    router.go('/map');
    await tester.pumpAndSettle();
    expect(find.text('位置情報サービスがオフです'), findsOneWidget);

    // 静的ルート /pin/compose が /pin/:id より優先される（PinComposeScreen）。
    router.go('/pin/compose');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Pin を立てる'), findsOneWidget);

    // 動的パラメータ付きルート（PinDetailScreen、近傍 0 件）。
    router.go('/pin/abc123');
    await tester.pumpAndSettle();
    expect(find.text('ここではまだあなただけです'), findsOneWidget);
  });
}
