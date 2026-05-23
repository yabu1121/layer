import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/location/location_service.dart';
import 'package:layer/features/map/map_controller.dart';

class _FakeLocationService implements LocationService {
  _FakeLocationService({
    this.serviceEnabled = true,
    this.permission = LocationPermissionStatus.granted,
    this.position = const LatLngPoint(35.0, 139.0),
  });

  bool serviceEnabled;
  LocationPermissionStatus permission;
  LatLngPoint position;
  int currentPositionCalls = 0;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermissionStatus> ensurePermission() async => permission;

  @override
  Future<LatLngPoint> currentPosition() async {
    currentPositionCalls++;
    return position;
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

ProviderContainer _container(_FakeLocationService loc) {
  final c = ProviderContainer(
    overrides: [locationServiceProvider.overrideWithValue(loc)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('サービス OFF → serviceDisabled', () async {
    final c = _container(_FakeLocationService(serviceEnabled: false));
    await c.read(mapControllerProvider.notifier).load();
    expect(c.read(mapControllerProvider).status, MapStatus.serviceDisabled);
  });

  test('権限拒否 → permissionDenied', () async {
    final c = _container(
      _FakeLocationService(permission: LocationPermissionStatus.denied),
    );
    await c.read(mapControllerProvider.notifier).load();
    final s = c.read(mapControllerProvider);
    expect(s.status, MapStatus.permissionDenied);
    expect(s.permanentlyDenied, isFalse);
  });

  test('恒久拒否 → permissionDenied かつ permanentlyDenied', () async {
    final c = _container(
      _FakeLocationService(permission: LocationPermissionStatus.deniedForever),
    );
    await c.read(mapControllerProvider.notifier).load();
    final s = c.read(mapControllerProvider);
    expect(s.status, MapStatus.permissionDenied);
    expect(s.permanentlyDenied, isTrue);
  });

  test('許可済み → ready で現在地センター', () async {
    final loc = _FakeLocationService(position: const LatLngPoint(35.68, 139.76));
    final c = _container(loc);
    await c.read(mapControllerProvider.notifier).load();
    final s = c.read(mapControllerProvider);
    expect(s.status, MapStatus.ready);
    expect(s.center, const LatLngPoint(35.68, 139.76));
  });

  test('recenter で center を取り直す', () async {
    final loc = _FakeLocationService(position: const LatLngPoint(35.0, 139.0));
    final c = _container(loc);
    await c.read(mapControllerProvider.notifier).load();

    loc.position = const LatLngPoint(34.0, 135.0);
    await c.read(mapControllerProvider.notifier).recenter();

    expect(c.read(mapControllerProvider).center, const LatLngPoint(34.0, 135.0));
    expect(loc.currentPositionCalls, 2); // load + recenter
  });
}
