import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../state/providers.dart';

class LiveHeader extends ConsumerWidget {
  const LiveHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref.watch(rankedIssuesProvider).valueOrNull ?? const [];
    final liveUsers = issues.fold<int>(
      0,
      (sum, r) => sum + r.issue.stats.liveUsers,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔥 지금 한국은',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '검색어를 그대로 베끼지 않고 다시 줄 세웁니다',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const _LiveDot(),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '${compactCount(liveUsers)}명 접속',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_controller),
      child: Container(
        width: 7,
        height: 7,
        margin: const EdgeInsets.only(bottom: 6),
        decoration: const BoxDecoration(
          color: AppColors.hot,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
