import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer/core/location/geocoding_service.dart';
import 'package:layer/core/location/location_service.dart';
import 'package:layer/core/media/image_picker_service.dart';
import 'package:layer/core/models/pin.dart';
import 'package:layer/features/map/pin_repository.dart';
import 'package:layer/features/pin_compose/image_upload_repository.dart';
import 'package:layer/features/pin_compose/pin_compose_controller.dart';

class _FakeLocation implements LocationService {
  _FakeLocation(this.pos);
  final LatLngPoint pos;
  @override
  Future<LatLngPoint> currentPosition() async => pos;
  @override
  Future<bool> isServiceEnabled() async => true;
  @override
  Future<LocationPermissionStatus> ensurePermission() async =>
      LocationPermissionStatus.granted;
  @override
  Future<bool> openAppSettings() async => true;
  @override
  Future<bool> openLocationSettings() async => true;
}

class _FakeGeocoding implements GeocodingService {
  _FakeGeocoding(this.label);
  String? label;
  @override
  Future<String?> reverseGeocode(double lat, double lng) async => label;
}

class _FakeImagePicker implements ImagePickerService {
  _FakeImagePicker(this.result);
  final PickedImage? result;
  @override
  Future<PickedImage?> pick() async => result;
}

class _FakeImageUpload implements ImageUploadRepository {
  String? uploadedContentType;
  @override
  Future<String> uploadPinImage(Uint8List bytes, String contentType) async {
    uploadedContentType = contentType;
    return 'https://cdn.example/pin-images/uploaded.jpg';
  }
}

class _FakePinRepo implements PinRepository {
  bool throwOnCreate = false;
  String? createdBody;
  double? createdLat;
  double? createdLng;
  String? createdImageUrl;
  String? createdEmotion;

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
    String? imageUrl,
    String? emotion,
  }) async {
    if (throwOnCreate) throw Exception('network');
    createdBody = body;
    createdLat = lat;
    createdLng = lng;
    createdImageUrl = imageUrl;
    createdEmotion = emotion;
    return Pin(
      id: 'new',
      ownerId: 'me',
      body: body,
      lat: lat,
      lng: lng,
      createdAt: DateTime(2026),
      author: const PinAuthor(id: 'me', userId: 'me', displayName: 'Me', icon: '😀'),
    );
  }
}

ProviderContainer _container({
  LatLngPoint pos = const LatLngPoint(35.0, 139.0),
  String? label = '東京都新宿区',
  _FakePinRepo? repo,
  _FakeImagePicker? picker,
  _FakeImageUpload? upload,
}) {
  final c = ProviderContainer(
    overrides: [
      locationServiceProvider.overrideWithValue(_FakeLocation(pos)),
      geocodingServiceProvider.overrideWithValue(_FakeGeocoding(label)),
      pinRepositoryProvider.overrideWithValue(repo ?? _FakePinRepo()),
      imagePickerServiceProvider
          .overrideWithValue(picker ?? _FakeImagePicker(null)),
      imageUploadRepositoryProvider
          .overrideWithValue(upload ?? _FakeImageUpload()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('initialize: 現在地と場所ラベルをセットする', () async {
    final c = _container(pos: const LatLngPoint(35.68, 139.76));
    await c.read(pinComposeControllerProvider.notifier).initialize();
    final s = c.read(pinComposeControllerProvider);
    expect(s.lat, 35.68);
    expect(s.lng, 139.76);
    expect(s.locationLabel, '東京都新宿区');
    expect(s.isLocating, isFalse);
    expect(s.hasLocation, isTrue);
  });

  test('updateLocation: 座標とラベルを更新する', () async {
    final c = _container(label: 'A');
    final n = c.read(pinComposeControllerProvider.notifier);
    await n.initialize();
    await n.updateLocation(34.0, 135.0);
    final s = c.read(pinComposeControllerProvider);
    expect(s.lat, 34.0);
    expect(s.lng, 135.0);
  });

  test('バリデーション: 本文 1-200 かつ位置必須', () async {
    final c = _container();
    final n = c.read(pinComposeControllerProvider.notifier);
    n.updateBody('hello');
    expect(c.read(pinComposeControllerProvider).canSubmit, isFalse); // 位置未設定

    await n.initialize();
    expect(c.read(pinComposeControllerProvider).canSubmit, isTrue);

    n.updateBody('   ');
    expect(c.read(pinComposeControllerProvider).canSubmit, isFalse); // 空白のみ

    n.updateBody('a' * 201);
    expect(c.read(pinComposeControllerProvider).canSubmit, isFalse); // 超過
    expect(c.read(pinComposeControllerProvider).remaining, 200 - 201);
  });

  test('submit 成功: trim した本文と座標で create する', () async {
    final repo = _FakePinRepo();
    final c = _container(repo: repo, pos: const LatLngPoint(35.0, 139.0));
    final n = c.read(pinComposeControllerProvider.notifier);
    await n.initialize();
    n.updateBody('  芝生最高  ');

    final result = await n.submit();

    expect(result, PinComposeResult.success);
    expect(repo.createdBody, '芝生最高');
    expect(repo.createdLat, 35.0);
    expect(repo.createdLng, 139.0);
    expect(c.read(pinComposeControllerProvider).isSubmitting, isFalse);
  });

  test('submit 無効: 本文未入力なら invalid（create しない）', () async {
    final repo = _FakePinRepo();
    final c = _container(repo: repo);
    final n = c.read(pinComposeControllerProvider.notifier);
    await n.initialize();

    expect(await n.submit(), PinComposeResult.invalid);
    expect(repo.createdBody, isNull);
  });

  test('画像添付: pick → submit で R2 にアップロードし image_url を渡す', () async {
    final repo = _FakePinRepo();
    final upload = _FakeImageUpload();
    final picker = _FakeImagePicker(
      PickedImage(bytes: Uint8List.fromList([1, 2, 3]), contentType: 'image/png'),
    );
    final c = _container(repo: repo, upload: upload, picker: picker);
    final n = c.read(pinComposeControllerProvider.notifier);
    await n.initialize();
    n.updateBody('写真つき');

    await n.pickImage();
    expect(c.read(pinComposeControllerProvider).image, isNotNull);

    final result = await n.submit();
    expect(result, PinComposeResult.success);
    expect(upload.uploadedContentType, 'image/png');
    expect(repo.createdImageUrl, 'https://cdn.example/pin-images/uploaded.jpg');
  });

  test('感情ラベル: 選択して submit すると emotion を渡す（再選択で解除）', () async {
    final repo = _FakePinRepo();
    final c = _container(repo: repo);
    final n = c.read(pinComposeControllerProvider.notifier);
    await n.initialize();
    n.updateBody('落ち着く');

    n.toggleEmotion('calm');
    expect(c.read(pinComposeControllerProvider).emotion, 'calm');
    n.toggleEmotion('calm'); // 再選択で解除
    expect(c.read(pinComposeControllerProvider).emotion, isNull);
    n.toggleEmotion('happy');

    await n.submit();
    expect(repo.createdEmotion, 'happy');
  });

  test('感情なし: emotion は null で create する', () async {
    final repo = _FakePinRepo();
    final c = _container(repo: repo);
    final n = c.read(pinComposeControllerProvider.notifier);
    await n.initialize();
    n.updateBody('感情なし');
    await n.submit();
    expect(repo.createdEmotion, isNull);
  });

  test('画像なし: image_url は null で create する', () async {
    final repo = _FakePinRepo();
    final c = _container(repo: repo);
    final n = c.read(pinComposeControllerProvider.notifier);
    await n.initialize();
    n.updateBody('画像なし');
    await n.submit();
    expect(repo.createdImageUrl, isNull);
  });

  test('clearImage: 選択を取り消せる', () async {
    final picker = _FakeImagePicker(
      PickedImage(bytes: Uint8List.fromList([9]), contentType: 'image/jpeg'),
    );
    final c = _container(picker: picker);
    final n = c.read(pinComposeControllerProvider.notifier);
    await n.initialize();
    await n.pickImage();
    expect(c.read(pinComposeControllerProvider).image, isNotNull);
    n.clearImage();
    expect(c.read(pinComposeControllerProvider).image, isNull);
  });

  test('submit 失敗: error を返し再送信できる', () async {
    final repo = _FakePinRepo()..throwOnCreate = true;
    final c = _container(repo: repo);
    final n = c.read(pinComposeControllerProvider.notifier);
    await n.initialize();
    n.updateBody('test');

    expect(await n.submit(), PinComposeResult.error);
    expect(c.read(pinComposeControllerProvider).isSubmitting, isFalse);

    repo.throwOnCreate = false;
    expect(await n.submit(), PinComposeResult.success); // 再送信
  });
}
