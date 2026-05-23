import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// ボトムタブの土台（issue #36）。
/// 地図 / 通知 / 自分 の 3 ブランチを [StatefulNavigationShell] で切り替える。
/// indexedStack なので各タブの状態（MapScreen の地図位置など）が保持される。
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          // 同じタブを再タップしたらそのブランチの初期位置へ戻す。
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: '地図',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: '通知',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '自分',
          ),
        ],
      ),
    );
  }
}
