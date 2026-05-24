import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/models/pin.dart';

Map<String, dynamic> _json({Object? imageUrl = _absent}) => {
      'id': 'p1',
      'userId': 'o1',
      'body': 'hello',
      'lat': 35.0,
      'lng': 139.0,
      'createdAt': '2026-01-01T00:00:00Z',
      'author': {
        'id': 'o1',
        'userId': 'h1',
        'displayName': 'name',
        'icon': '🐱',
      },
      if (imageUrl != _absent) 'imageUrl': imageUrl,
    };

const _absent = Object();

void main() {
  test('fromJson: imageUrl があれば取り込む', () {
    final p = Pin.fromJson(_json(imageUrl: 'https://cdn/x.jpg'));
    expect(p.imageUrl, 'https://cdn/x.jpg');
  });

  test('fromJson: imageUrl が無ければ null', () {
    expect(Pin.fromJson(_json()).imageUrl, isNull);
  });

  test('fromJson: imageUrl が空文字なら null', () {
    expect(Pin.fromJson(_json(imageUrl: '')).imageUrl, isNull);
  });
}
