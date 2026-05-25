import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/comment.dart';
import '../../core/models/emotion.dart';
import '../../core/models/pin.dart';
import '../../core/widgets/empty_view.dart';
import '../../core/widgets/photo_viewer.dart';
import '../map/map_controller.dart';
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

  Future<void> _deleteMain() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('この投稿を削除しますか？'),
        content: const Text('削除すると元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(pinDetailControllerProvider.notifier).deleteMain();
    if (!mounted) return;
    if (ok) {
      await ref.read(mapControllerProvider.notifier).refreshPins();
      navigator.maybePop();
    } else {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('削除に失敗しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pinDetailControllerProvider);
    final canDelete = state.mainPin != null &&
        state.myAuthor != null &&
        state.mainPin!.isMine(state.myAuthor!.id);

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
                  onClose: () => Navigator.of(context).maybePop(),
                  canDelete: canDelete,
                  onDelete: _deleteMain,
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
    required this.onClose,
    required this.canDelete,
    required this.onDelete,
    required this.onSelectPin,
    required this.onToggleReaction,
    required this.onRetry,
  });

  final PinDetailState state;
  final ScrollController scrollController;
  final VoidCallback onClose;
  final bool canDelete;
  final VoidCallback onDelete;
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
        SizedBox(
          height: 32,
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (canDelete)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '削除',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '閉じる',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                ),
              ),
            ],
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
          const SizedBox(height: 8),
          const EmptyView(
            message: 'ここではまだあなただけです',
            hint: '同じ場所に友達の Pin が立つと、ここに並びます',
            icon: Icons.place_outlined,
          ),
        ] else ...[
          const SizedBox(height: 16),
          Text('同じ場所の Pin', style: theme.textTheme.labelLarge),
          const Divider(height: 16),
          for (final pin in state.nearby)
            _PinCard(
              pin: pin,
              isMain: false,
              onTap: () => onSelectPin(pin.id),
            ),
        ],
        const Divider(height: 32),
        const _CommentSection(),
      ],
    );
  }
}

/// メイン Pin のコメント一覧と投稿欄。自分のコメントは削除できる（US-C3）。
class _CommentSection extends ConsumerStatefulWidget {
  const _CommentSection();

  @override
  ConsumerState<_CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends ConsumerState<_CommentSection> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok =
        await ref.read(pinDetailControllerProvider.notifier).addComment(text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _controller.clear();
    } else {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('コメントを送信できませんでした')));
    }
  }

  Future<void> _delete(String commentId) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(pinDetailControllerProvider.notifier)
        .deleteComment(commentId);
    if (!mounted || ok) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('コメントを削除できませんでした')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifier = ref.read(pinDetailControllerProvider.notifier);
    final comments =
        ref.watch(pinDetailControllerProvider.select((s) => s.comments));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('コメント ${comments.length}', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        if (comments.isEmpty)
          Text('まだコメントはありません', style: theme.textTheme.bodySmall)
        else
          for (final c in comments)
            _CommentTile(
              comment: c,
              canDelete: notifier.canDeleteComment(c),
              onDelete: () => _delete(c.id),
            ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLength: 200,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'コメントを書く…',
                  counterText: '',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              tooltip: '送信',
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.canDelete,
    required this.onDelete,
  });

  final Comment comment;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(comment.author.icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.author.displayName,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(_timeAgo(comment.createdAt),
                        style: theme.textTheme.bodySmall),
                  ],
                ),
                Text(comment.body),
              ],
            ),
          ),
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: '削除',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
        ],
      ),
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
              if (pin.imageUrl != null) ...[
                _PinImage(url: pin.imageUrl!),
                const SizedBox(height: 8),
              ],
              if (emotionByKey(pin.emotion) case final e?) ...[
                Chip(
                  label: Text('${e.emoji} ${e.label}'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(height: 8),
              ],
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
class _ReactionBar extends StatefulWidget {
  const _ReactionBar({
    required this.reactors,
    required this.reactedByMe,
    required this.onToggle,
  });

  final List<PinAuthor> reactors;
  final bool reactedByMe;
  final VoidCallback? onToggle;

  @override
  State<_ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<_ReactionBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  // タップ時に 1.0 → 1.3 → 1.0 と弾むスケール。
  late final Animation<double> _pop = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.3).chain(CurveTween(curve: Curves.easeOut)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
      weight: 50,
    ),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTap() {
    if (widget.onToggle == null) return;
    _controller.forward(from: 0); // ポップ演出
    widget.onToggle!();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.reactors.length;
    final shown = widget.reactors.take(5).toList();
    final extra = count - shown.length;
    return Row(
      children: [
        ScaleTransition(
          scale: _pop,
          child: widget.reactedByMe
              ? FilledButton.icon(
                  onPressed: _onTap,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text('わかる済み $count'),
                )
              : OutlinedButton.icon(
                  onPressed: _onTap,
                  icon: const Text('💛'),
                  label: Text('わかる $count'),
                ),
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

/// Pin の添付画像（US-B3）。読み込み中はインジケータ、失敗時はアイコン。
class _PinImage extends StatelessWidget {
  const _PinImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final fallback = Theme.of(context).colorScheme.surfaceContainerHighest;
    return GestureDetector(
      onTap: () => PhotoViewer.open(context, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Hero(
          tag: url,
          child: Image.network(
            url,
            width: double.infinity,
            height: 180,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                height: 180,
                alignment: Alignment.center,
                color: fallback,
                child: const CircularProgressIndicator(),
              );
            },
            errorBuilder: (context, error, stack) => Container(
              height: 180,
              alignment: Alignment.center,
              color: fallback,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      ),
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
