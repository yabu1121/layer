import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:layer/app/router.dart';
import 'package:layer/core/auth/current_user.dart';
import 'package:layer/core/location/geocoding_service.dart';
import 'package:layer/core/location/location_service.dart';
import 'package:layer/core/models/pin.dart';
import 'package:layer/core/models/user.dart';
import 'package:layer/features/map/pin_repository.dart';
import 'package:layer/features/notifications/app_notification.dart';
import 'package:layer/features/notifications/notification_repository.dart';

class _GrantedLocation implements LocationService {
  @override
  Future<bool> isServiceEnabled() async => true;
  @override
  Future<LocationPermissionStatus> ensurePermission() async =>
      LocationPermissionStatus.granted;
  @override
  Future<LatLngPoint> currentPosition() async => const LatLngPoint(35, 139);
  @override
  Future<bool> openAppSettings() async => true;
  @override
  Future<bool> openLocationSettings() async => true;
}

class _EmptyPins implements PinRepository {
  @override
  Future<List<Pin>> fetchVisible({bool friendsOnly = false}) async => const [];
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
  }) async =>
      throw UnimplementedError();
}

class _ZeroBadge implements NotificationRepository {
  @override
  Future<int> fetchUnreadCount() async => 0;
  @override
  Future<List<AppNotification>> list({int limit = 50}) async => const [];
  @override
  Future<void> markAllRead() async {}
}

class _StubGeocoding implements GeocodingService {
  @override
  Future<String?> reverseGeocode(double lat, double lng) async => '東京都';
}

ProviderContainer _container() => ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(_GrantedLocation()),
        geocodingServiceProvider.overrideWithValue(_StubGeocoding()),
        pinRepositoryProvider.overrideWithValue(_EmptyPins()),
        notificationRepositoryProvider.overrideWithValue(_ZeroBadge()),
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

void main() {
  testWidgets('3 タブを切り替えられる', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.go('/map');
    await tester.pumpAndSettle();
    expect(find.byType(GoogleMap), findsOneWidget);

    await tester.tap(find.text('通知'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'お知らせ'), findsOneWidget);

    await tester.tap(find.text('自分'));
    await tester.pumpAndSettle();
    expect(find.text('ログアウト'), findsOneWidget); // ProfileScreen

    await tester.tap(find.text('地図'));
    await tester.pumpAndSettle();
    expect(find.byType(GoogleMap), findsOneWidget);
  });

  testWidgets('FAB で /pin/compose に遷移する', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.go('/map');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Pin を立てる'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Pin を立てる'), findsOneWidget);
  });
}
