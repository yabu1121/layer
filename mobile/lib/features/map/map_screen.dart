import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/location/location_service.dart';
import '../notifications/notification_badge_controller.dart';
import 'map_controller.dart';
import 'map_markers.dart';

/// アプリ中心の地図画面（screens.md §2.4 / issue #33・#34・#35）。
/// 現在地センタリング・可視 Pin マーカー・クラスタリング・通知バッジを担う。
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = Completer<GoogleMapController>();

  /// google_maps_flutter 標準クラスタリングのグループ ID。
  static const _clusterManagerId = ClusterManagerId('pins');

  /// 絵文字マーカー生成は非同期（PNG 描画）のため結果を保持して描画する。
  Set<Marker> _markers = {};
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mapControllerProvider.notifier).load();
      _refreshBadge();
    });
    // 未読数を 30 秒ごとにポーリングする。
    _pollTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _refreshBadge());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _refreshBadge() =>
      ref.read(notificationBadgeProvider.notifier).refresh();

  Future<void> _rebuildMarkers(MapState state) async {
    final markers = await buildPinMarkers(
      pins: state.pins,
      myUserId: state.myUserId ?? '',
      clusterManagerId: _clusterManagerId,
      onTap: (pinId) => context.push('/pin/$pinId'),
    );
    if (mounted) setState(() => _markers = markers);
  }

  /// クラスタタップ: そのクラスタの範囲にズームインする。
  Future<void> _onClusterTap(Cluster cluster) async {
    if (!_mapController.isCompleted) return;
    final controller = await _mapController.future;
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(cluster.bounds, 60),
    );
  }

  Future<void> _onRecenter() async {
    await ref.read(mapControllerProvider.notifier).recenter();
    final center = ref.read(mapControllerProvider).center;
    if (center == null || !_mapController.isCompleted) return;
    final controller = await _mapController.future;
    await controller.animateCamera(
      CameraUpdate.newLatLng(LatLng(center.lat, center.lng)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pin / 自分判定が変わったらマーカーを作り直す。
    ref.listen<MapState>(mapControllerProvider, (prev, next) {
      if (prev?.pins != next.pins || prev?.myUserId != next.myUserId) {
        _rebuildMarkers(next);
      }
    });
    final state = ref.watch(mapControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Layer'),
        actions: const [_NotificationBadgeButton()],
      ),
      body: switch (state.status) {
        MapStatus.loading => const Center(child: CircularProgressIndicator()),
        MapStatus.serviceDisabled => _LocationGuide(
            title: '位置情報サービスがオフです',
            message: '地図を表示するには端末の位置情報をオンにしてください。',
            actionLabel: '位置情報設定を開く',
            onAction: () =>
                ref.read(locationServiceProvider).openLocationSettings(),
            onRetry: () => ref.read(mapControllerProvider.notifier).load(),
          ),
        MapStatus.permissionDenied => _LocationGuide(
            title: '位置情報の許可が必要です',
            message: '地図に現在地を表示するには位置情報を許可してください。',
            actionLabel: state.permanentlyDenied ? '設定を開く' : '再試行',
            onAction: state.permanentlyDenied
                ? () => ref.read(locationServiceProvider).openAppSettings()
                : () => ref.read(mapControllerProvider.notifier).load(),
            onRetry: state.permanentlyDenied
                ? () => ref.read(mapControllerProvider.notifier).load()
                : null,
          ),
        MapStatus.ready => _MapView(
            center: state.center!,
            markers: _markers,
            clusterManagerId: _clusterManagerId,
            onClusterTap: _onClusterTap,
            onMapCreated: (controller) {
              if (!_mapController.isCompleted) {
                _mapController.complete(controller);
              }
            },
            onRecenter: _onRecenter,
          ),
      },
    );
  }
}

class _NotificationBadgeButton extends ConsumerWidget {
  const _NotificationBadgeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(notificationBadgeProvider);
    return IconButton(
      tooltip: 'お知らせ',
      onPressed: () async {
        await context.push('/notifications');
        // 通知画面で既読化された可能性があるので戻ったら再取得する。
        ref.read(notificationBadgeProvider.notifier).refresh();
      },
      icon: count > 0
          ? Badge(
              label: Text('$count'),
              child: const Icon(Icons.notifications),
            )
          : const Icon(Icons.notifications_none),
    );
  }
}

class _MapView extends StatelessWidget {
  const _MapView({
    required this.center,
    required this.markers,
    required this.clusterManagerId,
    required this.onClusterTap,
    required this.onMapCreated,
    required this.onRecenter,
  });

  final LatLngPoint center;
  final Set<Marker> markers;
  final ClusterManagerId clusterManagerId;
  final void Function(Cluster) onClusterTap;
  final void Function(GoogleMapController) onMapCreated;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(center.lat, center.lng),
            zoom: 15,
          ),
          markers: markers,
          clusterManagers: {
            ClusterManager(
              clusterManagerId: clusterManagerId,
              onClusterTap: onClusterTap,
            ),
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: false, // 自前の現在地ボタンを使う
          onMapCreated: onMapCreated,
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            heroTag: 'recenter',
            onPressed: onRecenter,
            tooltip: '現在地',
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}

class _LocationGuide extends StatelessWidget {
  const _LocationGuide({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.onRetry,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off, size: 48),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('再試行')),
          ],
        ),
      ),
    );
  }
}
