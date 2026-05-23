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

class _FakePinRepository implements PinRepository {
  _FakePinRepository(this.pins);
  final List<Pin> pins;
  @override
  Future<List<Pin>> fetchVisible() async => pins;
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

Widget _app(_FakeLocationService loc) => ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(loc),
        pinRepositoryProvider.overrideWithValue(_FakePinRepository(const [])),
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
}
