import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../archive/archive_page.dart';
import '../me/me_page.dart';
import '../trending/trending_page.dart';

enum HomeTab {
  trending(
    '실시간',
    Icons.local_fire_department_outlined,
    Icons.local_fire_department,
    '/',
  ),
  archive('지난 이슈', Icons.inventory_2_outlined, Icons.inventory_2, '/archive'),
  me('나', Icons.person_outline, Icons.person, '/me');

  const HomeTab(this.label, this.icon, this.activeIcon, this.path);

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String path;
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.tab});

  final HomeTab tab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (tab) {
          HomeTab.trending => const TrendingPage(),
          HomeTab.archive => const ArchivePage(),
          HomeTab.me => const MePage(),
        },
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          height: 62,
          selectedIndex: tab.index,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) => context.go(HomeTab.values[i].path),
          destinations: [
            for (final t in HomeTab.values)
              NavigationDestination(
                icon: Icon(t.icon, color: AppColors.textTertiary),
                selectedIcon: Icon(t.activeIcon, color: AppColors.hot),
                label: t.label,
              ),
          ],
        ),
      ),
    );
  }
}
