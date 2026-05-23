import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/pin.dart';
import 'friends_controller.dart';

/// 友達の検索・申請画面（screens.md §2.8 上部 / issue #40）。
/// 申請の承認・一覧・招待は別 issue（#41/#42）。
class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  Future<void> _send(BuildContext context, WidgetRef ref) async {
    final ok = await ref.read(friendsControllerProvider.notifier).sendRequest();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('申請を送れませんでした')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(friendsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('友達')),
      body: Column(
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
          Expanded(child: _SearchResult(state: state, onSend: () => _send(context, ref))),
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
        return const Center(child: CircularProgressIndicator());
      case FriendSearchStatus.notFound:
        return const Center(child: Text('ユーザーが見つかりませんでした'));
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
