import 'package:go_router/go_router.dart';

import '../../features/home/home_shell.dart';
import '../../features/room/room_page.dart';

/// URL 전략은 기본값(해시)을 쓴다.
/// `/#/issue/abc` 형태라 정적 호스팅에 rewrite 규칙 없이 바로 올라간다.
/// path 전략 전환은 Phase 4(호스팅 확정 후). → plan.md 참조
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'trending',
      builder: (_, __) => const HomeShell(tab: HomeTab.trending),
    ),
    GoRoute(
      path: '/archive',
      name: 'archive',
      builder: (_, __) => const HomeShell(tab: HomeTab.archive),
    ),
    GoRoute(
      path: '/me',
      name: 'me',
      builder: (_, __) => const HomeShell(tab: HomeTab.me),
    ),
    GoRoute(
      path: '/issue/:id',
      name: 'issue',
      builder: (_, state) => RoomPage(issueId: state.pathParameters['id']!),
    ),
  ],
);
