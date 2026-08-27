import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/post.dart';
import '../../../domain/ranking/ranked_issue.dart';

/// "나중에 온 사람" 전용 요약 카드.
///
/// 이 서비스의 차별점은 실시간 대화가 아니라, 늦게 들어와도 흐름을 따라잡을 수
/// 있다는 것이다. 방에 들어오면 대화 로그가 아니라 이 카드가 먼저 보인다.
class CatchUpCard extends StatelessWidget {
  const CatchUpCard({super.key, required this.ranked, required this.posts});

  final RankedIssue ranked;
  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    final highlights = [...posts]
      ..sort((a, b) => b.highlightScore.compareTo(a.highlightScore));
    final top = highlights.take(3).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, size: 15, color: AppColors.warm),
              const SizedBox(width: 5),
              const Text(
                '지금까지의 흐름',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '${relativeTime(ranked.issue.firstSeenAt)} 시작',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ranked.issue.summary ?? '아직 요약할 만큼 대화가 쌓이지 않았습니다.',
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _SourceLine(ranked: ranked),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Text(
              '가장 많이 반응한 글',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            for (final post in top) _HighlightRow(post: post),
          ],
          if (ranked.issue.relatedKeywords.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in ranked.issue.relatedKeywords)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '#$k',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceLine extends StatelessWidget {
  const _SourceLine({required this.ranked});

  final RankedIssue ranked;

  @override
  Widget build(BuildContext context) {
    final ranks = [...ranked.issue.ranks]
      ..sort((a, b) => a.rank.compareTo(b.rank));

    return Row(
      children: [
        Expanded(
          child: Text(
            ranks.map((r) => '${r.source.label} ${r.rank}위').join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'HotScore ${ranked.breakdown.total.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: heatColor(ranked.breakdown.total),
          ),
        ),
      ],
    );
  }
}

class _HighlightRow extends StatelessWidget {
  const _HighlightRow({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('·  ', style: TextStyle(color: AppColors.textTertiary)),
          Expanded(
            child: Text(
              post.text ?? '(이미지)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '❤ ${post.likes}',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.hot,
            ),
          ),
        ],
      ),
    );
  }
}
