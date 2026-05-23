import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/location/geocoding_service.dart';
import 'package:layer/core/models/pin.dart';
import 'package:layer/features/map/pin_repository.dart';
import 'package:layer/features/pin_detail/pin_detail_screen.dart';

Pin _pin(String id) => Pin(
      id: id,
      ownerId: 'o$id',
      body: 'body-$id',
      lat: 35.0,
      lng: 139.0,
      createdAt: DateTime(2026, 1, 1),
      author: PinAuthor(
        id: 'o$id',
        userId: 'h$id',
        displayName: 'name-$id',
        icon: '🐱',
      ),
    );

class _FakePinRepo implements PinRepository {
  _FakePinRepo(this.nearby);
  final List<Pin> nearby;

  @override
  Future<Pin> getById(String id) async => _pin(id);
  @override
  Future<List<Pin>> getNearby(String id) async => nearby;
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

Widget _app(List<Pin> nearby) => ProviderScope(
      overrides: [
        pinRepositoryProvider.overrideWithValue(_FakePinRepo(nearby)),
        geocodingServiceProvider.overrideWithValue(_FakeGeocoding()),
      ],
      child: const MaterialApp(home: PinDetailScreen(pinId: 'p1')),
    );

void main() {
  testWidgets('メイン Pin と近傍を表示する', (tester) async {
    await tester.pumpWidget(_app([_pin('p2')]));
    await tester.pumpAndSettle();

    expect(find.text('新宿御苑'), findsOneWidget);
    expect(find.text('body-p1'), findsOneWidget); // メイン
    expect(find.text('body-p2'), findsOneWidget); // 近傍
    expect(find.text('── 同じ場所の Pin ──'), findsOneWidget);
    expect(find.text('わかる'), findsWidgets); // ボタン表示
  });

  testWidgets('近傍 0 件で空メッセージ', (tester) async {
    await tester.pumpWidget(_app(const []));
    await tester.pumpAndSettle();

    expect(find.text('body-p1'), findsOneWidget);
    expect(find.text('ここではまだあなただけです'), findsOneWidget);
  });
}
