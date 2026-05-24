import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/models/pin.dart';

/// 自分の Pin のリング色（青系）。
const mineMarkerColor = Color(0xFF1E88E5);

/// 友達の Pin のリング色（オレンジ系）。
const friendMarkerColor = Color(0xFFFB8C00);

/// 自分／友達でマーカーのリング色を返す（screens.md §2.4）。
Color markerColorFor({required bool mine}) =>
    mine ? mineMarkerColor : friendMarkerColor;

/// 投稿者の絵文字を中央に描いた円形マーカー画像を生成する。
/// `google_maps_flutter` のマーカーは絵文字テキストを直接描けないため、
/// Canvas で PNG を作って [BitmapDescriptor] にする。
Future<BitmapDescriptor> renderPinMarkerIcon({
  required String emoji,
  required Color ringColor,
  double size = 120,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final center = Offset(size / 2, size / 2);

  canvas.drawCircle(center, size / 2, Paint()..color = ringColor);
  canvas.drawCircle(center, size / 2 - 10, Paint()..color = Colors.white);

  final tp = TextPainter(
    text: TextSpan(
      text: emoji.isEmpty ? '📍' : emoji,
      style: TextStyle(fontSize: size * 0.5),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));

  final image =
      await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
}

/// 可視 Pin からマーカー集合を作る（screens.md §2.4 表示ロジック）。
///
/// 各マーカーに [clusterManagerId] を付けることで google_maps_flutter 標準の
/// クラスタリング（同一地点付近のまとまり）に乗せる。
/// - 自分の Pin: 青系リング + 自分のアイコン
/// - 友達の Pin: オレンジ系リング + 投稿者のアイコン
/// - タップで [onTap]（PinDetail を開く導線。遷移実装は別 issue）
Future<Set<Marker>> buildPinMarkers({
  required List<Pin> pins,
  required String myUserId,
  required ClusterManagerId clusterManagerId,
  required void Function(String pinId) onTap,
}) async {
  final markers = <Marker>{};
  for (final pin in pins) {
    final mine = pin.isMine(myUserId);
    // Web ではカスタム画像マーカーが描画できず「壊れた画像」になるため、
    // 標準マーカー（色分け）を使う。実機は絵文字付きカスタムマーカー。
    final BitmapDescriptor icon;
    if (kIsWeb) {
      // 現在地（青）と区別するため、投稿 Pin は 自分=赤 / 友達=オレンジ。
      icon = BitmapDescriptor.defaultMarkerWithHue(
        mine ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange,
      );
    } else {
      icon = await renderPinMarkerIcon(
        emoji: pin.author.icon,
        ringColor: markerColorFor(mine: mine),
      );
    }
    markers.add(
      Marker(
        markerId: MarkerId(pin.id),
        position: LatLng(pin.lat, pin.lng),
        clusterManagerId: clusterManagerId,
        icon: icon,
        infoWindow: InfoWindow(
          title: '${pin.author.icon} ${pin.author.displayName}',
          snippet: pin.body,
        ),
        onTap: () => onTap(pin.id),
      ),
    );
  }
  return markers;
}
