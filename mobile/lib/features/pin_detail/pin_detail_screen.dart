import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/pin.dart';
import 'pin_detail_controller.dart';

/// 場所の Pin 詳細（発見の核）。ボトムシートでメイン Pin と同じ場所の Pin を並べる。
/// （screens.md §2.6 / issue #38）
class PinDetailScreen extends ConsumerStatefulWidget {
  const PinDetailScreen({super.key, required this.pinId});

  final String pinId;

  @override
  ConsumerState<PinDetailScreen> createState() => _PinDetailScreenState();
}

class _PinDetailScreenState extends ConsumerState<PinDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pinDetailControllerProvider.notifier).load(widget.pinId);
    });
  }

  Future<void> _toggleReaction() async {
    final ok =
        await ref.read(pinDetailControllerProvider.notifier).toggleReaction();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('「わかる」を更新できませんでした')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pinDetailControllerProvider);

    return Scaffold(
      backgroundColor: Colors.black54, // 背後の地図を暗くするスクリム
      body: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.25,
          maxChildSize: 0.95,
          snap: true,
          snapSizes: const [0.25, 0.5, 0.95],
          builder: (context, scrollController) {
            return GestureDetector(
              onTap: () {}, // シート内タップは閉じない
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: _SheetContent(
                  state: state,
                  scrollController: scrollController,
                  onSelectPin: (id) => ref
                      .read(pinDetailControllerProvider.notifier)
                      .selectPin(id),
                  onToggleReaction: _toggleReaction,
                  onRetry: () => ref
                      .read(pinDetailControllerProvider.notifier)
                      .load(widget.pinId),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SheetContent extends StatelessWidget {
  const _SheetContent({
    required this.state,
    required this.scrollController,
    required this.onSelectPin,
    required this.onToggleReaction,
    required this.onRetry,
  });

  final PinDetailState state;
  final ScrollController scrollController;
  final void Function(String pinId) onSelectPin;
  final VoidCallback onToggleReaction;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state.status == PinDetailStatus.loading) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(48),
        child: CircularProgressIndicator(),
      ));
    }
    if (state.status == PinDetailStatus.error || state.mainPin == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('読み込みに失敗しました'),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('再試行')),
            ],
          ),
        ),
      );
    }

    final main = state.mainPin!;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            const Icon(Icons.place, size: 20),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                state.locationLabel ?? 'この場所',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        Text('Pin ${state.totalCount} 件', style: theme.textTheme.bodySmall),
        const Divider(height: 24),
        _PinCard(
          pin: main,
          isMain: true,
          reactors: state.reactors,
          reactedByMe: state.reactedByMe,
          onToggleReaction: onToggleReaction,
        ),
        if (state.nearby.isEmpty) ...[
          const SizedBox(height: 24),
          Center(
            child: Text(
              'ここではまだあなただけです',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ] else ...[
          const SizedBox(height: 16),
          Text('── 同じ場所の Pin ──', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          for (final pin in state.nearby)
            _PinCard(
              pin: pin,
              isMain: false,
              onTap: () => onSelectPin(pin.id),
            ),
        ],
      ],
    );
  }
}

class _PinCard extends StatelessWidget {
  const _PinCard({
    required this.pin,
    required this.isMain,
    this.onTap,
    this.reactors,
    this.reactedByMe = false,
    this.onToggleReaction,
  });

  final Pin pin;
  final bool isMain;
  final VoidCallback? onTap;

  /// メイン Pin のみ非 null（共感者一覧）。null の近傍カードは表示専用。
  final List<PinAuthor>? reactors;
  final bool reactedByMe;
  final VoidCallback? onToggleReaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(pin.author.icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Text(pin.author.displayName,
                      style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(_timeAgo(pin.createdAt),
                      style: theme.textTheme.bodySmall),
                ],
              ),
              Text('@${pin.author.userId}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(pin.body),
              const SizedBox(height: 8),
              if (reactors != null)
                _ReactionBar(
                  reactors: reactors!,
                  reactedByMe: reactedByMe,
                  onToggle: onToggleReaction,
                )
              else
                // 近傍カードは表示のみ（タップでメインに切替）。
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Text('💛'),
                  label: const Text('わかる'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「わかる」ボタン + 共感者アイコン（最大 5 + 残数）。
class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.reactors,
    required this.reactedByMe,
    required this.onToggle,
  });

  final List<PinAuthor> reactors;
  final bool reactedByMe;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final count = reactors.length;
    final shown = reactors.take(5).toList();
    final extra = count - shown.length;
    return Row(
      children: [
        reactedByMe
            ? FilledButton.icon(
                onPressed: onToggle,
                icon: const Icon(Icons.check, size: 18),
                label: Text('わかる済み $count'),
              )
            : OutlinedButton.icon(
                onPressed: onToggle,
                icon: const Text('💛'),
                label: Text('わかる $count'),
              ),
        const SizedBox(width: 8),
        for (final r in shown)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Text(r.icon, style: const TextStyle(fontSize: 16)),
          ),
        if (extra > 0)
          Text('+$extra', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// 簡易な相対時刻表示。
String _timeAgo(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'たった今';
  if (diff.inHours < 1) return '${diff.inMinutes}分前';
  if (diff.inDays < 1) return '${diff.inHours}時間前';
  if (diff.inDays < 7) return '${diff.inDays}日前';
  return '${time.year}/${time.month}/${time.day}';
}
