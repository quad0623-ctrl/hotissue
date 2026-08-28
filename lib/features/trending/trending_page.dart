import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/ranking/ranked_issue.dart';
import '../../state/providers.dart';
import 'widgets/animated_rank_list.dart';
import 'widgets/issue_card.dart';
import 'widgets/live_header.dart';
import 'widgets/mode_selector.dart';

class TrendingPage extends ConsumerWidget {
  const TrendingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranked = ref.watch(rankedIssuesProvider);

    return ranked.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.hot),
      ),
      error: (e, _) => _ErrorView(message: '$e'),
      data: (issues) => CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: LiveHeader()),
          SliverToBoxAdapter(
            child: ModeSelector(
              selected: ref.watch(rankingModeProvider),
              onChanged: (mode) {
                ref.read(rankingServiceProvider).reset();
                ref.read(rankingModeProvider.notifier).state = mode;
              },
            ),
          ),
          // 순위가 바뀌면 카드가 자리를 옮긴다.
          // 5분에 한 번뿐인 변화라 놓치면 안 된다.
          SliverToBoxAdapter(
            child: AnimatedRankList(
              items: issues,
              itemHeight: issueCardHeight(context),
              itemBuilder: (context, item) => IssueCard(
                ranked: item,
                onTap: () => context.push('/issue/${item.issue.id}'),
                onExplain: () => _showBreakdown(context, item),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: _Footer()),
        ],
      ),
    );
  }

  void _showBreakdown(BuildContext context, RankedIssue ranked) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BreakdownSheet(ranked: ranked),
    );
  }
}

/// "왜 이 순위인가"를 그대로 공개한다. 알고리즘 불신을 미리 차단하는 장치.
class _BreakdownSheet extends StatelessWidget {
  const _BreakdownSheet({required this.ranked});

  final RankedIssue ranked;

  @override
  Widget build(BuildContext context) {
    final b = ranked.breakdown;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ranked.issue.keyword,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'HotScore ${b.total.toStringAsFixed(1)}점 · ${ranked.position}위',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: heatColor(b.total),
            ),
          ),
          const SizedBox(height: 20),
          for (final entry in b.asMap.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MetricRow(label: entry.key, value: entry.value),
            ),
          const SizedBox(height: 8),
          const Text(
            '순위 = (순위·상승세·확산도·참여도의 가중 평균) × 신선도\n'
            '포털 검색량만 그대로 쓰지 않고, 여러 소스에 동시에 뜨는지와\n'
            '실제로 이 방에서 사람들이 떠드는지를 함께 봅니다.',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: AppColors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation(heatColor(value * 100)),
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${(value * 100).round()}',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
      child: Text(
        '데이터 출처: ${AppConfig.preferredMode.label}\n'
        '수집 소스와 가중치는 설정 > 정렬 기준에서 확인할 수 있습니다.\n'
        '가입 없이 익명으로 참여합니다.',
        style: const TextStyle(
          fontSize: 11,
          height: 1.6,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off,
              color: AppColors.textTertiary,
              size: 40,
            ),
            const SizedBox(height: 12),
            const Text('순위를 불러오지 못했습니다'),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
