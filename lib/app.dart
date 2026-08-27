import 'package:flutter/material.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class HotIssueApp extends StatelessWidget {
  const HotIssueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '핫이슈',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
      builder: (context, child) {
        // 모바일 우선 서비스라 데스크톱 브라우저에서도 폭을 제한해
        // 같은 레이아웃을 보게 한다. (Phase 4에서 반응형 2단 레이아웃 도입)
        return ColoredBox(
          color: AppColors.bg,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: MediaQuery.withClampedTextScaling(
                minScaleFactor: 1.0,
                maxScaleFactor: 1.3,
                child: child ?? const SizedBox(),
              ),
            ),
          ),
        );
      },
    );
  }
}
