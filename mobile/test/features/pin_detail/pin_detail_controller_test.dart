import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/location/geocoding_service.dart';
import 'package:layer/core/models/pin.dart';
import 'package:layer/features/map/pin_repository.dart';
import 'package:layer/features/pin_detail/pin_detail_controller.dart';

Pin _pin(String id) => Pin(
      id: id,
      ownerId: 'owner-$id',
      body: 'body-$id',
      lat: 35.0,
      lng: 139.0,
      createdAt: DateTime(2026, 1, 1),
      author: PinAuthor(
        id: 'owner-$id',
        userId: 'h$id',
        displayName: 'name-$id',
        icon: '🐱',
      ),
    );

class _FakePinRepo implements PinRepository {
  _FakePinRepo({this.nearbyById = const {}, this.throwIt = false});

  final Map<String, List<Pin>> nearbyById;
  bool throwIt;

  @override
  Future<Pin> getById(String id) async {
    if (throwIt) throw Exception('boom');
    return _pin(id);
  }

  @override
  Future<List<Pin>> getNearby(String id) async => nearbyById[id] ?? const [];

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

class _FakeGeocoding implements GeocodingService {
  @override
  Future<String?> reverseGeocode(double lat, double lng) async => '新宿御苑';
}

ProviderContainer _container(_FakePinRepo repo) {
  final c = ProviderContainer(
    overrides: [
      pinRepositoryProvider.overrideWithValue(repo),
      geocodingServiceProvider.overrideWithValue(_FakeGeocoding()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('load: メイン Pin・近傍・場所ラベルを取得する', () async {
    final repo = _FakePinRepo(nearbyById: {
      'p1': [_pin('p2'), _pin('p3')],
    });
    final c = _container(repo);
    await c.read(pinDetailControllerProvider.notifier).load('p1');
    final s = c.read(pinDetailControllerProvider);

    expect(s.status, PinDetailStatus.ready);
    expect(s.mainPin!.id, 'p1');
    expect(s.nearby.length, 2);
    expect(s.locationLabel, '新宿御苑');
    expect(s.totalCount, 3); // メイン + 近傍2
  });

  test('近傍 0 件: nearby は空、totalCount は 1', () async {
    final c = _container(_FakePinRepo());
    await c.read(pinDetailControllerProvider.notifier).load('p1');
    final s = c.read(pinDetailControllerProvider);
    expect(s.nearby, isEmpty);
    expect(s.totalCount, 1);
  });

  test('selectPin: 内容を差し替える', () async {
    final repo = _FakePinRepo(nearbyById: {
      'p1': [_pin('p2')],
    });
    final c = _container(repo);
    final n = c.read(pinDetailControllerProvider.notifier);
    await n.load('p1');
    expect(c.read(pinDetailControllerProvider).mainPin!.id, 'p1');

    await n.selectPin('p2');
    expect(c.read(pinDetailControllerProvider).mainPin!.id, 'p2');
  });

  test('失敗時は error', () async {
    final c = _container(_FakePinRepo(throwIt: true));
    await c.read(pinDetailControllerProvider.notifier).load('p1');
    expect(c.read(pinDetailControllerProvider).status, PinDetailStatus.error);
  });
}
