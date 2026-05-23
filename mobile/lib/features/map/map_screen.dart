import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/location/location_service.dart';
import 'map_controller.dart';

/// アプリ中心の地図画面（screens.md §2.4 / issue #33）。
/// 本 issue では地図表示と現在地センタリングのみ。Pin 描画は別 issue。
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = Completer<GoogleMapController>();

  @override
  void initState() {
    super.initState();
    // build 後に位置情報の取得を開始する。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mapControllerProvider.notifier).load();
    });
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
    final state = ref.watch(mapControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Layer')),
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
            onMapCreated: (c) {
              if (!_mapController.isCompleted) _mapController.complete(c);
            },
            onRecenter: _onRecenter,
          ),
      },
    );
  }
}

class _MapView extends StatelessWidget {
  const _MapView({
    required this.center,
    required this.onMapCreated,
    required this.onRecenter,
  });

  final LatLngPoint center;
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
