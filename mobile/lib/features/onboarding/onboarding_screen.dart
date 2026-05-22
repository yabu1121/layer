import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'onboarding_controller.dart';

/// 初回プロフィール設定画面（screens.md §2.3 / issue #32）。
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final TextEditingController _userIdController;
  final _userIdFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 生成済みの仮 user_id をフィールドにプリフィルする。
    final initial = ref.read(onboardingControllerProvider);
    _userIdController = TextEditingController(text: initial.userId);
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _userIdFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final result =
        await ref.read(onboardingControllerProvider.notifier).submit();
    if (!mounted) return;
    switch (result) {
      case OnboardingSubmitResult.success:
        context.go('/map');
      case OnboardingSubmitResult.userIdTaken:
        _userIdFocus.requestFocus(); // エラー表示は state 経由で出る
      case OnboardingSubmitResult.networkError:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('登録に失敗しました。もう一度お試しください')),
          );
      case OnboardingSubmitResult.invalid:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingControllerProvider);
    final notifier = ref.read(onboardingControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール設定')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('あなたのことを教えてください', style: theme.textTheme.titleMedium),
            const SizedBox(height: 24),
            // 名前
            TextField(
              decoration: InputDecoration(
                labelText: '名前',
                hintText: 'リョウ',
                border: const OutlineInputBorder(),
                errorText: state.displayNameErrorText,
              ),
              maxLength: 20,
              onChanged: notifier.updateDisplayName,
            ),
            const SizedBox(height: 16),
            // アイコン
            Text('アイコン', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final icon in onboardingIcons)
                  _IconChoice(
                    icon: icon,
                    selected: state.icon == icon,
                    onTap: () => notifier.updateIcon(icon),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // ユーザー ID
            TextField(
              controller: _userIdController,
              focusNode: _userIdFocus,
              decoration: InputDecoration(
                labelText: 'ユーザー ID',
                prefixText: '@ ',
                border: const OutlineInputBorder(),
                errorText: state.userIdErrorText,
              ),
              onChanged: notifier.updateUserId,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed:
                  (state.isValid && !state.isSubmitting) ? _submit : null,
              child: state.isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('はじめる'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String icon;
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
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
        ),
        child: Text(icon, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}
