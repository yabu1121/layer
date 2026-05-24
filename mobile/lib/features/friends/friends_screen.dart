import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/pin.dart';
import '../../core/share/share_service.dart';
import 'friend_repository.dart';
import 'friends_controller.dart';

/// 友達の検索・申請・受信申請の承認/拒否（screens.md §2.8 / issue #40・#41）。
/// 友達一覧表示・招待共有は #42。
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(friendsControllerProvider.notifier).loadLists();
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send() async {
    final ok = await ref.read(friendsControllerProvider.notifier).sendRequest();
    if (!ok && mounted) _snack('申請を送れませんでした');
  }

  Future<void> _accept(IncomingRequest req) async {
    final ok = await ref.read(friendsControllerProvider.notifier).accept(req);
    if (mounted) {
      _snack(ok ? '${req.requester.displayName} と友達になりました' : '承認に失敗しました');
    }
  }

  Future<void> _reject(IncomingRequest req) async {
    final ok = await ref.read(friendsControllerProvider.notifier).reject(req);
    if (!ok && mounted) _snack('拒否に失敗しました');
  }

  Future<void> _unfriend(PinAuthor friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${friend.displayName} を友達から外しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('解除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok =
        await ref.read(friendsControllerProvider.notifier).unfriend(friend);
    if (!ok && mounted) _snack('解除に失敗しました');
  }

  Future<void> _invite() async {
    final message =
        await ref.read(friendsControllerProvider.notifier).inviteMessage();
    if (message == null) {
      if (mounted) _snack('招待リンクを作成できませんでした');
      return;
    }
    await ref.read(shareServiceProvider).share(message);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(friendsControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('友達')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                prefixText: '@',
                hintText: 'ユーザー ID を入力',
                border: OutlineInputBorder(),
              ),
              onChanged:
                  ref.read(friendsControllerProvider.notifier).onQueryChanged,
            ),
          ),
          _SearchResult(state: state, onSend: _send),
          if (state.incoming.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('申請中（${state.incoming.length}）',
                  style: theme.textTheme.titleSmall),
            ),
            for (final req in state.incoming)
              _IncomingTile(
                request: req,
                onAccept: () => _accept(req),
                onReject: () => _reject(req),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('友達（${state.friends.length}）',
                style: theme.textTheme.titleSmall),
          ),
          if (state.friends.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('友達を招待して、Layer をはじめましょう')),
            )
          else
            for (final f in state.friends)
              ListTile(
                leading: Text(f.icon, style: const TextStyle(fontSize: 24)),
                title: Text(f.displayName),
                subtitle: Text('@${f.userId}'),
                onTap: () => context.push('/users/${f.id}', extra: f),
                trailing: IconButton(
                  icon: const Icon(Icons.person_remove_outlined),
                  tooltip: '友達を解除',
                  onPressed: () => _unfriend(f),
                ),
              ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: _invite,
              icon: const Icon(Icons.share),
              label: const Text('友達を招待'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResult extends StatelessWidget {
  const _SearchResult({required this.state, required this.onSend});

  final FriendsState state;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    switch (state.searchStatus) {
      case FriendSearchStatus.idle:
        return const SizedBox.shrink();
      case FriendSearchStatus.loading:
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      case FriendSearchStatus.notFound:
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('ユーザーが見つかりませんでした')),
        );
      case FriendSearchStatus.found:
        return _UserCard(
          user: state.foundUser!,
          relation: state.relation!,
          isSending: state.isSending,
          onSend: onSend,
        );
    }
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.relation,
    required this.isSending,
    required this.onSend,
  });

  final PinAuthor user;
  final FriendRelation relation;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListTile(
        leading: Text(user.icon, style: const TextStyle(fontSize: 24)),
        title: Text(user.displayName),
        subtitle: Text('@${user.userId}'),
        trailing: _trailing(),
      ),
    );
  }

  Widget _trailing() {
    switch (relation) {
      case FriendRelation.self:
        return const Text('あなた自身です');
      case FriendRelation.friend:
        return const Text('友達');
      case FriendRelation.pending:
        return const Text('申請中');
      case FriendRelation.available:
        return FilledButton(
          onPressed: isSending ? null : onSend,
          child: isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('友達申請'),
        );
    }
  }
}

class _IncomingTile extends StatelessWidget {
  const _IncomingTile({
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  final IncomingRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final u = request.requester;
    return ListTile(
      leading: Text(u.icon, style: const TextStyle(fontSize: 24)),
      title: Text(u.displayName),
      subtitle: Text('@${u.userId}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(onPressed: onAccept, child: const Text('承認')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onReject, child: const Text('拒否')),
        ],
      ),
    );
  }
}
