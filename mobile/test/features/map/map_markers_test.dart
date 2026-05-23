import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:layer/core/models/pin.dart';
import 'package:layer/features/map/map_markers.dart';

Pin _pin(String id, String ownerId) => Pin(
      id: id,
      ownerId: ownerId,
      body: 'body $id',
      lat: 35.0,
      lng: 139.0,
      createdAt: DateTime(2026, 1, 1),
      author: PinAuthor(
        id: ownerId,
        userId: 'handle_$ownerId',
        displayName: 'name_$ownerId',
        icon: '🐱',
      ),
    );

void main() {
  test('markerColorFor: 自分と友達で色が異なる', () {
    expect(
      markerColorFor(mine: true),
      isNot(markerColorFor(mine: false)),
    );
  });

  testWidgets('buildPinMarkers: 件数・位置・onTap', (tester) async {
    String? tapped;
    late Set<Marker> markers;
    // toImage は実 async のため runAsync 内で実行する。
    await tester.runAsync(() async {
      markers = await buildPinMarkers(
        pins: [_pin('p1', 'me-id'), _pin('p2', 'friend-id')],
        myUserId: 'me-id',
        onTap: (id) => tapped = id,
      );
    });

    expect(markers.length, 2);
    final m = markers.firstWhere((x) => x.markerId.value == 'p1');
    expect(m.position, const LatLng(35.0, 139.0));
    m.onTap!();
    expect(tapped, 'p1');
  });

  testWidgets('0 件なら空集合', (tester) async {
    late Set<Marker> markers;
    await tester.runAsync(() async {
      markers = await buildPinMarkers(
        pins: const [],
        myUserId: 'me-id',
        onTap: (_) {},
      );
    });
    expect(markers, isEmpty);
  });
}
