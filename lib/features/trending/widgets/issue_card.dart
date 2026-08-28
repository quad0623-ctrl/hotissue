import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/issue.dart';
import '../../../domain/ranking/ranked_issue.dart';

/// 카드 기본 높이. [AnimatedRankList] 가 위치를 계산하려면 전부 같아야 한다.
///
/// 내용이 전부 1줄 고정(`maxLines: 1`)이라 성립한다.
/// 요약이 없는 이슈도 같은 높이를 쓰도록 자리를 비워둔다.
const double kIssueCardBaseHeight = 118;

/// 글자 배율을 반영한 실제 높이.
/// [app.dart] 가 배율을 1.3으로 묶어두고 있어 그만큼만 늘어난다.
double issueCardHeight(BuildContext context) =>
    kIssueCardBaseHeight * MediaQuery.textScalerOf(context).scale(1.0);

class IssueCard extends StatefulWidget {
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
  State<IssueCard> createState() => _IssueCardState();
}

class _IssueCardState extends State<IssueCard>
    with SingleTickerProviderStateMixin {
  /// 갱신 순간 이 카드가 바뀌었음을 알리는 짧은 물듦.
  /// **바뀐 카드만** 빛나야 의미가 있다. 전부 빛나면 아무것도 말하지 않는 것과 같다.
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  /// 물듦의 색. 순위가 오르면 붉게, 내리면 푸르게.
  Color _flashColor = AppColors.hot12;

  @override
  void didUpdateWidget(IssueCard old) {
    super.didUpdateWidget(old);

    final before = old.ranked;
    final after = widget.ranked;

    final moved = before.position != after.position;
    final rescored =
        (before.breakdown.total - after.breakdown.total).abs() >= 0.5;
    final sourcesChanged =
        before.issue.ranks.length != after.issue.ranks.length;

    if (!moved && !rescored && !sourcesChanged) return;

    _flashColor = moved
        ? (after.position < before.position
            ? AppColors.hot12
            : AppColors.cool12)
        : AppColors.white08;

    _flash.forward(from: 0);
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final issue = widget.ranked.issue;
    final score = widget.ranked.breakdown.total;

    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) {
        // 0 → 1 → 0 으로 물들었다 빠진다
        final t = _flash.isDismissed
            ? 0.0
            : (_flash.value < 0.25
                ? _flash.value / 0.25
                : 1 - (_flash.value - 0.25) / 0.75);

        return DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(Colors.transparent, _flashColor, t),
            border: const Border(
              bottom: BorderSide(color: AppColors.border),
            ),
          ),
          child: child,
        );
      },
      child: InkWell(
        onTap: widget.onTap,
        // 고정 높이라 내용이 넘칠 때 노란 줄무늬 대신 조용히 잘리게 한다
        child: ClipRect(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RankColumn(ranked: widget.ranked),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
                          _StatusTag(status: widget.ranked.status),
                        ],
                      ),
                      const SizedBox(height: 3),
                      // 요약이 없어도 자리를 비워 높이를 맞춘다
                      Text(
                        issue.summary ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 7),
                      _SourceBadges(ranks: issue.ranks),
                      const SizedBox(height: 7),
                      _StatsRow(
                        issue: issue,
                        score: score,
                        onExplain: widget.onExplain,
                      ),
                    ],
                  ),
                ),
                if (issue.imageUrl != null) ...[
                  const SizedBox(width: 12),
                  _Thumbnail(url: issue.imageUrl!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 기사 썸네일.
///
/// 구글 트렌드가 함께 주는 이미지를 원본 위치에서 그대로 불러온다.
/// 우리 서버에 복제하지 않는다 — 저장하는 건 URL 뿐이다.
///
/// **실패해도 자리를 유지한다.** 카드 높이가 고정이라 크기가 흔들리면
/// 순위 이동 애니메이션의 위치 계산이 어긋난다.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url});

  final String url;

  static const double _size = 46;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _size,
        height: _size,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          // 실패·로딩 모두 같은 크기의 빈 자리로 대체한다
          errorBuilder: (_, __, ___) => const _ThumbnailPlaceholder(),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : const _ThumbnailPlaceholder(),
        ),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: AppColors.surfaceHigh);
  }
}

/// 카드 하단 지표.
///
/// 예전에는 `글 0 · 추천 0 · 0명` 을 항상 보여줬다. 사용자가 없는 동안
/// 모든 카드가 0을 달고 있으면 **화면이 죽었다고 광고하는 셈**이다.
/// 0인 값은 숨기고, 대신 늘 존재하는 실제 값(검색량)을 앞에 세운다.
class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.issue,
    required this.score,
    required this.onExplain,
  });

  final Issue issue;
  final double score;
  final VoidCallback onExplain;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    // 구글 트렌드가 주는 대략적 검색량. 수집해 놓고 여태 화면에 안 쓰던 값이다.
    final traffic = issue.approxTraffic;
    if (traffic != null && traffic.isNotEmpty) {
      chips.add(_Stat(icon: Icons.search, value: traffic, highlight: true));
    }

    if (issue.stats.posts > 0) {
      chips.add(
        _Stat(
          icon: Icons.forum_outlined,
          value: compactCount(issue.stats.posts),
        ),
      );
    }
    if (issue.stats.likes > 0) {
      chips.add(
        _Stat(
          icon: Icons.favorite_border,
          value: compactCount(issue.stats.likes),
        ),
      );
    }
    if (issue.stats.liveUsers > 0) {
      chips.add(
        _Stat(
          icon: Icons.person_outline,
          value: '${issue.stats.liveUsers}',
          highlight: issue.stats.liveUsers > 30,
        ),
      );
    }

    return Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          chips[i],
        ],
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
        mainAxisSize: MainAxisSize.min,
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

/// 소스 뱃지. **한 줄을 넘지 않아야 한다** — 카드 높이가 고정이라 넘치면 잘린다.
class _SourceBadges extends StatelessWidget {
  const _SourceBadges({required this.ranks});

  final List<SourceRank> ranks;

  static const _visible = 3;

  @override
  Widget build(BuildContext context) {
    final sorted = [...ranks]..sort((a, b) => a.rank.compareTo(b.rank));
    final shown = sorted.take(_visible).toList();
    final hidden = sorted.length - shown.length;

    return SizedBox(
      height: 17,
      child: Row(
        children: [
          for (final r in shown) ...[
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
            const SizedBox(width: 5),
          ],
          if (hidden > 0)
            Text(
              '+$hidden',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});

  final IssueStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == IssueStatus.steady) return const SizedBox.shrink();

    final (color, bg) = switch (status) {
      IssueStatus.rising => (AppColors.warm, AppColors.warm12),
      IssueStatus.hot => (AppColors.hot, AppColors.hot12),
      IssueStatus.cooling => (AppColors.cool, AppColors.cool12),
      IssueStatus.archived => (AppColors.textTertiary, AppColors.white08),
      IssueStatus.steady => (AppColors.textTertiary, AppColors.white08),
    };

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
    final color = highlight ? AppColors.warm : AppColors.textTertiary;

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
