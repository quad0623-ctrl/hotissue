import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/issue.dart';
import '../../../domain/ranking/ranked_issue.dart';

class IssueCard extends StatelessWidget {
  const IssueCard({
    super.key,
    required this.ranked,
    required this.onTap,
    required this.onExplain,
  });

  final RankedIssue ranked;
  final VoidCallback onTap;
  final VoidCallback onExplain;

  @override
  Widget build(BuildContext context) {
    final issue = ranked.issue;
    final score = ranked.breakdown.total;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RankColumn(ranked: ranked),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          issue.keyword,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _StatusTag(status: ranked.status),
                    ],
                  ),
                  if (issue.summary != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      issue.summary!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _SourceBadges(ranks: issue.ranks),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Stat(
                        icon: Icons.forum_outlined,
                        value: compactCount(issue.stats.posts),
                      ),
                      const SizedBox(width: 12),
                      _Stat(
                        icon: Icons.favorite_border,
                        value: compactCount(issue.stats.likes),
                      ),
                      const SizedBox(width: 12),
                      _Stat(
                        icon: Icons.person_outline,
                        value: '${issue.stats.liveUsers}',
                        highlight: issue.stats.liveUsers > 30,
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: onExplain,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Text(
                              score.toStringAsFixed(0),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: heatColor(score),
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.help_outline,
                              size: 13,
                              color: AppColors.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankColumn extends StatelessWidget {
  const _RankColumn({required this.ranked});

  final RankedIssue ranked;

  @override
  Widget build(BuildContext context) {
    final delta = ranked.positionDelta;

    return SizedBox(
      width: 30,
      child: Column(
        children: [
          Text(
            '${ranked.position}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              height: 1,
              color: ranked.position <= 3
                  ? AppColors.hot
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          if (ranked.isNew)
            const Text(
              'NEW',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                color: AppColors.warm,
              ),
            )
          else if (delta != null && delta != 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  delta > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 14,
                  color: delta > 0 ? AppColors.up : AppColors.down,
                ),
                Text(
                  '${delta.abs()}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: delta > 0 ? AppColors.up : AppColors.down,
                  ),
                ),
              ],
            )
          else
            const Text(
              '-',
              style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
            ),
        ],
      ),
    );
  }
}

class _SourceBadges extends StatelessWidget {
  const _SourceBadges({required this.ranks});

  final List<SourceRank> ranks;

  @override
  Widget build(BuildContext context) {
    final sorted = [...ranks]..sort((a, b) => a.rank.compareTo(b.rank));

    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final r in sorted.take(4))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${r.source.code} ${r.rank}위',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        if (sorted.length > 4)
          Text(
            '+${sorted.length - 4}',
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textTertiary,
            ),
          ),
      ],
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});

  final IssueStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (status) {
      IssueStatus.rising => (AppColors.warm, AppColors.warm12),
      IssueStatus.hot => (AppColors.hot, AppColors.hot12),
      IssueStatus.cooling => (AppColors.cool, AppColors.cool12),
      IssueStatus.archived => (AppColors.textTertiary, AppColors.white08),
      IssueStatus.steady => (AppColors.textTertiary, AppColors.white08),
    };

    if (status == IssueStatus.steady) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.hot : AppColors.textTertiary;

    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
