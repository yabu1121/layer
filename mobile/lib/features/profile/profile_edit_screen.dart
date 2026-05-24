import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/user.dart';
import '../onboarding/onboarding_controller.dart' show onboardingIcons;
import 'profile_edit_controller.dart';

/// プロフィール（名前・アイコン・ユーザーID）の編集（US-A8 / FR-1.4）。
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key, required this.user});

  final User user;

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.user.displayName);
  late final TextEditingController _userId =
      TextEditingController(text: widget.user.userId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileEditControllerProvider.notifier).load(widget.user);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _userId.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final result =
        await ref.read(profileEditControllerProvider.notifier).submit();
    if (!mounted) return;
    switch (result) {
      case ProfileEditResult.success:
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('プロフィールを更新しました')));
        context.pop();
      case ProfileEditResult.userIdTaken:
        break; // フィールド下にエラー表示（state 経由）
      case ProfileEditResult.networkError:
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('保存に失敗しました')));
      case ProfileEditResult.invalid:
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('入力内容を確認してください')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileEditControllerProvider);
    final notifier = ref.read(profileEditControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール編集')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            maxLength: 20,
            onChanged: notifier.updateDisplayName,
            decoration: InputDecoration(
              labelText: '名前',
              counterText: '',
              errorText: state.displayNameErrorText,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('アイコン', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final emoji in onboardingIcons)
                _IconChoice(
                  emoji: emoji,
                  selected: state.icon == emoji,
                  onTap: () => notifier.updateIcon(emoji),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _userId,
            onChanged: notifier.updateUserId,
            decoration: InputDecoration(
              labelText: 'ユーザーID',
              prefixText: '@',
              errorText: state.userIdErrorText,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: state.isValid && !state.isSubmitting ? _save : null,
            child: state.isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer : null,
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}
