import 'package:flutter_test/flutter_test.dart';
import 'package:hotissue/domain/models/issue.dart';
import 'package:hotissue/domain/models/trend_source.dart';
import 'package:hotissue/domain/ranking/hot_score.dart';

void main() {
  final now = DateTime(2026, 8, 27, 12);

  Issue makeIssue({
    required String id,
    List<SourceRank> ranks = const [],
    RoomStats stats = const RoomStats(),
    Duration sinceLastSeen = Duration.zero,
    Duration age = const Duration(hours: 1),
  }) {
    return Issue(
      id: id,
      keyword: id,
      ranks: ranks,
      firstSeenAt: now.subtract(age),
      lastSeenAt: now.subtract(sinceLastSeen),
      stats: stats,
    );
  }

  SourceRank rank(TrendSource source, int r, {int? prev}) => SourceRank(
        source: source,
        rank: r,
        previousRank: prev,
        observedAt: now,
      );

  group('HotScoreEngine', () {
    const engine = HotScoreEngine();

    test('상위 순위가 하위 순위보다 높은 점수를 받는다', () {
      final top = makeIssue(
        id: 'top',
        ranks: [rank(TrendSource.googleTrends, 1, prev: 1)],
      );
      final bottom = makeIssue(
        id: 'bottom',
        ranks: [rank(TrendSource.googleTrends, 18, prev: 18)],
      );

      expect(
        engine.score(top, now: now).total,
        greaterThan(engine.score(bottom, now: now).total),
      );
    });

    test('여러 소스에 동시에 뜨면 확산도 점수가 오른다', () {
      final single = makeIssue(
        id: 'single',
        ranks: [rank(TrendSource.googleTrends, 5, prev: 5)],
      );
      final multi = makeIssue(
        id: 'multi',
        ranks: [
          rank(TrendSource.googleTrends, 5, prev: 5),
          rank(TrendSource.yna, 5, prev: 5),
          rank(TrendSource.khan, 5, prev: 5),
        ],
      );

      final a = engine.score(single, now: now);
      final b = engine.score(multi, now: now);

      expect(b.diversityScore, greaterThan(a.diversityScore));
      expect(b.total, greaterThan(a.total));
    });

    // 회귀 방지: 예전 확산도 식은 `distinct / (TrendSource.values.length / 2)`
    // 였다. 이러면 enum 에서 소스를 빼는 순간 분모가 줄어 **모든 이슈가 만점**을
    // 받는다. 실제로 수집 소스를 8개→7개로 정리하면서 드러난 버그다.
    // 이제 등록된 소스 개수와 무관한 절대 기준을 쓴다.
    test('확산도는 등록된 소스 개수에 좌우되지 않는다', () {
      SourceRank at(TrendSource s) => rank(s, 5, prev: 5);

      final one = makeIssue(id: '1', ranks: [at(TrendSource.googleTrends)]);
      final two = makeIssue(
        id: '2',
        ranks: [at(TrendSource.googleTrends), at(TrendSource.yna)],
      );
      final three = makeIssue(
        id: '3',
        ranks: [
          at(TrendSource.googleTrends),
          at(TrendSource.yna),
          at(TrendSource.khan),
        ],
      );

      expect(engine.score(one, now: now).diversityScore, closeTo(0.15, 0.001));
      expect(engine.score(two, now: now).diversityScore, closeTo(0.5, 0.001));
      expect(engine.score(three, now: now).diversityScore, closeTo(1.0, 0.001));

      // 3곳을 넘어도 1.0 을 넘지 않는다
      final many = makeIssue(
        id: 'many',
        ranks: TrendSource.visible.map(at).toList(),
      );
      expect(engine.score(many, now: now).diversityScore, closeTo(1.0, 0.001));
    });

    test('순위가 오르는 중이면 내려가는 중보다 상승세 점수가 높다', () {
      final rising = makeIssue(
        id: 'rising',
        ranks: [rank(TrendSource.yna, 3, prev: 15)],
      );
      final falling = makeIssue(
        id: 'falling',
        ranks: [rank(TrendSource.yna, 3, prev: 1)],
      );

      expect(
        engine.score(rising, now: now).velocityScore,
        greaterThan(engine.score(falling, now: now).velocityScore),
      );
    });

    test('오래 관측되지 않으면 신선도 감쇠로 점수가 떨어진다', () {
      final fresh = makeIssue(
        id: 'fresh',
        ranks: [rank(TrendSource.yna, 2, prev: 2)],
      );
      final stale = makeIssue(
        id: 'stale',
        ranks: [rank(TrendSource.yna, 2, prev: 2)],
        sinceLastSeen: const Duration(minutes: 90), // 정확히 반감기
      );

      final f = engine.score(fresh, now: now);
      final s = engine.score(stale, now: now);

      expect(s.freshness, closeTo(0.5, 0.01));
      expect(s.total, closeTo(f.total / 2, 0.01));
    });

    test('참여도는 로그 스케일이라 거대 방이 독점하지 않는다', () {
      final small = makeIssue(
        id: 'small',
        ranks: [rank(TrendSource.yna, 5, prev: 5)],
        stats: const RoomStats(posts: 10, comments: 10),
      );
      final huge = makeIssue(
        id: 'huge',
        ranks: [rank(TrendSource.yna, 5, prev: 5)],
        stats: const RoomStats(posts: 1000, comments: 1000),
      );

      final a = engine.score(small, now: now).engagementScore;
      final b = engine.score(huge, now: now).engagementScore;

      expect(b, greaterThan(a));
      // 활동량은 100배지만 점수는 4배를 넘지 않는다
      expect(b / a, lessThan(4));
    });

    test('모든 세부 점수는 0~1 범위를 벗어나지 않는다', () {
      final extreme = makeIssue(
        id: 'extreme',
        ranks: [
          rank(TrendSource.googleTrends, 1),
          rank(TrendSource.yna, 1, prev: 20),
        ],
        stats: const RoomStats(
          posts: 99999,
          comments: 99999,
          likes: 99999,
          reactions: 99999,
          liveUsers: 9999,
        ),
      );

      final b = engine.score(extreme, now: now);
      for (final v in b.asMap.values) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
      expect(b.total, inInclusiveRange(0.0, 100.0));
    });

    test('sort는 점수 내림차순을 보장한다', () {
      final issues = [
        makeIssue(id: 'a', ranks: [rank(TrendSource.mk, 19, prev: 19)]),
        makeIssue(id: 'b', ranks: [rank(TrendSource.googleTrends, 1, prev: 9)]),
        makeIssue(id: 'c', ranks: [rank(TrendSource.yna, 10, prev: 10)]),
      ];

      final sorted = engine.sort(issues, now: now);
      expect(sorted.first.id, 'b');
      expect(sorted.last.id, 'a');
    });

    test('감쇠가 충분히 진행되면 아카이브로 분류된다', () {
      final old = makeIssue(
        id: 'old',
        ranks: [rank(TrendSource.yna, 5, prev: 5)],
        sinceLastSeen: const Duration(hours: 6),
      );

      expect(engine.classify(old, now: now), IssueStatus.archived);
    });
  });
}
