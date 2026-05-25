import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/models/emotion.dart';
import '../map/map_controller.dart';
import 'pin_compose_controller.dart';

/// 新しい Pin を投稿する画面（screens.md §2.5 / issue #37）。
class PinComposeScreen extends ConsumerStatefulWidget {
  const PinComposeScreen({super.key});

  @override
  ConsumerState<PinComposeScreen> createState() => _PinComposeScreenState();
}

class _PinComposeScreenState extends ConsumerState<PinComposeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pinComposeControllerProvider.notifier).initialize();
    });
  }

  Future<void> _submit() async {
    final result =
        await ref.read(pinComposeControllerProvider.notifier).submit();
    if (!mounted) return;
    switch (result) {
      case PinComposeResult.success:
        // 地図の Pin を取り直してから戻る。
        await ref.read(mapControllerProvider.notifier).refreshPins();
        if (mounted) context.pop();
      case PinComposeResult.error:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('投稿に失敗しました。もう一度お試しください')),
          );
      case PinComposeResult.invalid:
        break;
    }
  }

  Future<void> _onClose() async {
    final state = ref.read(pinComposeControllerProvider);
    if (!state.isDirty) {
      context.pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('編集を破棄しますか？'),
        content: const Text('入力した内容は保存されません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('続ける'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('破棄'),
          ),
        ],
      ),
    );
    if ((discard ?? false) && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pinComposeControllerProvider);
    final notifier = ref.read(pinComposeControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _onClose,
        ),
        title: const Text('Pin を立てる'),
        actions: [
          TextButton(
            onPressed: state.canSubmit ? _submit : null,
            child: state.isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('投稿'),
          ),
        ],
      ),
      body: ListView(
        children: [
          SizedBox(
            height: 220,
            child: switch ((state.isLocating, state.hasLocation)) {
              (true, _) => const Center(child: CircularProgressIndicator()),
              (false, false) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('現在地を取得できませんでした'),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: notifier.initialize,
                        child: const Text('再試行'),
                      ),
                    ],
                  ),
                ),
              (false, true) => GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(state.lat!, state.lng!),
                    zoom: 16,
                  ),
                  markers: {
                    Marker(
                      markerId: const MarkerId('compose'),
                      position: LatLng(state.lat!, state.lng!),
                      draggable: true,
                      onDragEnd: (pos) =>
                          notifier.updateLocation(pos.latitude, pos.longitude),
                    ),
                  },
                  myLocationEnabled: true,
                ),
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.place, size: 20),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        state.locationLabel ??
                            (state.isLocating ? '場所を取得中…' : 'この場所'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'ピンをドラッグして位置を調整できます',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  maxLength: PinComposeState.maxBody,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'ここで感じたこと…',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: notifier.updateBody,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in emotionOptions)
                      ChoiceChip(
                        label: Text('${e.emoji} ${e.label}'),
                        selected: state.emotion == e.key,
                        onSelected: (_) => notifier.toggleEmotion(e.key),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (state.image != null)
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          state.image!.bytes,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: IconButton.filledTonal(
                          onPressed: notifier.clearImage,
                          icon: const Icon(Icons.close),
                          tooltip: '写真を削除',
                        ),
                      ),
                    ],
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => notifier.pickImage(),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('写真を追加'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
