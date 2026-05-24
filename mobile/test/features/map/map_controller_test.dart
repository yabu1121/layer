import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/auth/current_user.dart';
import 'package:layer/core/location/location_service.dart';
import 'package:layer/core/models/pin.dart';
import 'package:layer/core/models/user.dart';
import 'package:layer/features/map/map_controller.dart';
import 'package:layer/features/map/pin_repository.dart';

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
  }) async =>
      throw UnimplementedError();
}

Pin _pin(String id, String ownerId) => Pin(
      id: id,
      ownerId: ownerId,
      body: 'b',
      lat: 35,
      lng: 139,
      createdAt: DateTime(2026, 1, 1),
      author: PinAuthor(
        id: ownerId,
        userId: 'h',
        displayName: 'n',
        icon: '🐱',
      ),
    );

const _me = User(id: 'me-id', userId: 'me', displayName: 'Me', icon: '😀');

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

ProviderContainer _container(
  _FakeLocationService loc, {
  List<Pin> pins = const [],
}) {
  final c = ProviderContainer(
    overrides: [
      locationServiceProvider.overrideWithValue(loc),
      pinRepositoryProvider.overrideWithValue(_FakePinRepository(pins)),
      currentUserProvider.overrideWith((ref) async => _me),
    ],
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

  test('ready 後に可視 Pin と自分の UUID を取得する', () async {
    final loc = _FakeLocationService();
    final c = _container(
      loc,
      pins: [_pin('p1', 'me-id'), _pin('p2', 'friend-id')],
    );
    await c.read(mapControllerProvider.notifier).load();
    final s = c.read(mapControllerProvider);
    expect(s.status, MapStatus.ready);
    expect(s.pins.length, 2);
    expect(s.myUserId, 'me-id');
    expect(s.pins.first.isMine(s.myUserId!), isTrue);
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
