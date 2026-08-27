import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models/issue.dart';
import '../../state/providers.dart';

/// 식은 이슈들의 보관소.
///
/// "나중에 온 사람들은 그걸 보고 이런 이슈가 있었구나 한다"는 아이디어의
/// 핵심 화면. 실시간 탭이 소비하는 화면이라면 여기는 남는 화면이다.
class ArchivePage extends ConsumerWidget {
  const ArchivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);

    return archive.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.hot),
      ),
      error: (e, _) => Center(child: Text('불러오기 실패: $e')),
      data: (issues) {
        final grouped = _groupByDay(issues);

        return CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _Header()),
            for (final entry in grouped.entries) ...[
              SliverToBoxAdapter(child: _DayHeader(label: entry.key)),
              SliverList.builder(
                itemCount: entry.value.length,
                itemBuilder: (_, i) => _ArchiveTile(
                  issue: entry.value[i],
                  onTap: () => context.push('/issue/${entry.value[i].id}'),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        );
      },
    );
  }

  Map<String, List<Issue>> _groupByDay(List<Issue> issues) {
    final sorted = [...issues]
      ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));

    final map = <String, List<Issue>>{};
    for (final issue in sorted) {
      final key = _dayLabel(issue.lastSeenAt);
      map.putIfAbsent(key, () => []).add(issue);
    }
    return map;
  }

  static String _dayLabel(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    return '${time.month}월 ${time.day}일';
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📦 지난 이슈',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          SizedBox(height: 2),
          Text(
            '식은 이슈도 기록은 남습니다. 그때 무슨 일이 있었는지 읽어보세요',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: AppColors.border)),
        ],
      ),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({required this.issue, required this.onTap});

  final Issue issue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total =
        issue.stats.posts + issue.stats.comments + issue.stats.reactions;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 34,
              decoration: BoxDecoration(
                color: total > 400 ? AppColors.hot : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    issue.keyword,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    issue.summary ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${compactCount(total)} 반응',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  relativeTime(issue.lastSeenAt),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
