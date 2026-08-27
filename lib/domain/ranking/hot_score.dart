import 'dart:math' as math;

import '../models/issue.dart';

/// HotScore 가중치. 운영하면서 튜닝하는 값이라 상수가 아니라 객체로 둔다.
class HotScoreWeights {
  const HotScoreWeights({
    this.source = 0.35,
    this.velocity = 0.25,
    this.diversity = 0.15,
    this.engagement = 0.25,
    this.halfLife = const Duration(minutes: 90),
    this.engagementSaturation = 400,
    this.rankHorizon = 20,
  });

  /// 외부 순위의 절대 위치
  final double source;

  /// 순위 상승 속도
  final double velocity;

  /// 여러 소스에 동시 등장했는가 (한 소스만의 노이즈 배제)
  final double diversity;

  /// 우리 서비스 안의 참여도
  final double engagement;

  /// 이 시간이 지나면 점수가 절반이 된다
  final Duration halfLife;

  /// 참여도 점수가 1.0에 수렴하는 기준 활동량
  final double engagementSaturation;

  /// 몇 위까지를 유의미하게 볼 것인가
  final int rankHorizon;

  /// 기본 프리셋: 균형형
  static const balanced = HotScoreWeights();

  /// 속보형 - 지금 막 튀어오르는 것 위주
  static const breaking = HotScoreWeights(
    source: 0.25,
    velocity: 0.45,
    diversity: 0.15,
    engagement: 0.15,
    halfLife: Duration(minutes: 40),
  );

  /// 토론형 - 우리 방이 활발한 것 위주
  static const discussion = HotScoreWeights(
    source: 0.20,
    velocity: 0.10,
    diversity: 0.10,
    engagement: 0.60,
    halfLife: Duration(hours: 6),
  );
}

/// 점수 산출 내역. UI에서 "왜 이 순위인가"를 그대로 보여주기 위해 분해해서 반환한다.
/// (알고리즘 불투명성이 커뮤니티 불신으로 이어지는 걸 막는 게 목적)
class HotScoreBreakdown {
  const HotScoreBreakdown({
    required this.sourceScore,
    required this.velocityScore,
    required this.diversityScore,
    required this.engagementScore,
    required this.freshness,
    required this.total,
  });

  final double sourceScore; // 0~1
  final double velocityScore; // 0~1
  final double diversityScore; // 0~1
  final double engagementScore; // 0~1
  final double freshness; // 0~1 (감쇠 계수)

  /// 최종 점수 0~100
  final double total;

  Map<String, double> get asMap => {
        '순위': sourceScore,
        '상승세': velocityScore,
        '확산도': diversityScore,
        '참여도': engagementScore,
        '신선도': freshness,
      };
}

/// 핫이슈의 자체 정렬 엔진.
///
///   HotScore = (Ws·순위 + Wv·상승세 + Wd·확산도 + We·참여도) × 신선도 × 100
///
/// 포털 순위를 그대로 베끼지 않는 이유:
///  1. 포털 순위는 검색량만 본다 → 광고/어뷰징/연예인 팬덤 총공에 취약
///  2. 여러 소스에 동시에 뜬 키워드가 진짜 이슈일 확률이 높다 (확산도)
///  3. 우리 방에서 실제로 사람들이 떠드는지가 최종 검증이다 (참여도)
class HotScoreEngine {
  const HotScoreEngine({this.weights = HotScoreWeights.balanced});

  final HotScoreWeights weights;

  HotScoreBreakdown score(Issue issue, {DateTime? now}) {
    final at = now ?? DateTime.now();

    return HotScoreBreakdown(
      sourceScore: _sourceScore(issue),
      velocityScore: _velocityScore(issue),
      diversityScore: _diversityScore(issue),
      engagementScore: _engagementScore(issue),
      freshness: _freshness(issue, at),
      total: _total(issue, at),
    );
  }

  double _total(Issue issue, DateTime at) {
    final weighted = weights.source * _sourceScore(issue) +
        weights.velocity * _velocityScore(issue) +
        weights.diversity * _diversityScore(issue) +
        weights.engagement * _engagementScore(issue);

    final sum = weights.source +
        weights.velocity +
        weights.diversity +
        weights.engagement;

    return (weighted / sum) * _freshness(issue, at) * 100;
  }

  /// 등장한 소스들에서의 평균 순위 품질. 1위=1.0, rankHorizon위=0.0
  double _sourceScore(Issue issue) {
    if (issue.ranks.isEmpty) return 0;

    var weightedSum = 0.0;
    var weightTotal = 0.0;

    for (final r in issue.ranks) {
      final quality = ((weights.rankHorizon - r.rank + 1) / weights.rankHorizon)
          .clamp(0.0, 1.0);
      weightedSum += r.source.weight * quality;
      weightTotal += r.source.weight;
    }

    return weightTotal == 0 ? 0 : weightedSum / weightTotal;
  }

  /// 순위 상승 속도. 하락은 0.5 미만, 신규 진입은 높은 점수.
  double _velocityScore(Issue issue) {
    if (issue.ranks.isEmpty) return 0.5;

    var sum = 0.0;
    for (final r in issue.ranks) {
      if (r.isNew) {
        sum += 0.9; // 신규 진입은 강한 상승 신호로 취급하되 1.0은 주지 않는다
      } else {
        // delta를 -1~1로 압축한 뒤 0~1로 이동
        final normalized = (r.delta / weights.rankHorizon).clamp(-1.0, 1.0);
        sum += (normalized + 1) / 2;
      }
    }
    return sum / issue.ranks.length;
  }

  /// 몇 곳에서 동시에 확인됐는가.
  ///
  /// 예전엔 `TrendSource.values.length / 2` 로 나눴는데 이건 틀린 식이었다.
  /// enum 에서 소스를 빼면 분모가 줄어 **모든 이슈가 만점**을 받는다.
  /// 등록된 소스 개수가 아니라 "의미 있는 확산"의 절대 기준을 쓴다.
  ///   1곳 → 0.15 (검색에만 뜬 것. 어뷰징이거나 단순 호기심)
  ///   2곳 → 0.5
  ///   3곳 이상 → 1.0 (검색과 보도가 함께 움직인다)
  double _diversityScore(Issue issue) {
    final distinct = issue.ranks.map((r) => r.source).toSet().length;
    if (distinct <= 1) return 0.15;
    return ((distinct - 1) / 2).clamp(0.0, 1.0);
  }

  /// 우리 방 참여도. 로그 스케일로 눌러서 초대형 방이 순위를 독점하지 않게 한다.
  double _engagementScore(Issue issue) {
    final s = issue.stats;
    final raw = s.posts * 1.0 +
        s.comments * 2.0 +
        s.likes * 3.0 +
        s.reactions * 0.5 +
        s.liveUsers * 4.0;

    if (raw <= 0) return 0;

    return (math.log(1 + raw) / math.log(1 + weights.engagementSaturation))
        .clamp(0.0, 1.0);
  }

  /// 마지막 관측 이후 반감기 감쇠. 오래된 이슈는 자연히 아카이브로 밀린다.
  double _freshness(Issue issue, DateTime at) {
    final elapsed = at.difference(issue.lastSeenAt).inSeconds;
    if (elapsed <= 0) return 1.0;

    final halfLifeSeconds = weights.halfLife.inSeconds;
    return math.pow(0.5, elapsed / halfLifeSeconds).toDouble();
  }

  /// 이슈 상태 자동 판정. 아카이브 이동 배치의 판단 근거로도 쓴다.
  IssueStatus classify(Issue issue, {DateTime? now}) {
    final b = score(issue, now: now);

    if (b.freshness < 0.15) return IssueStatus.archived;
    if (b.velocityScore >= 0.75 && b.sourceScore >= 0.4) {
      return IssueStatus.rising;
    }
    if (b.total >= 60 && b.engagementScore >= 0.5) return IssueStatus.hot;
    if (b.velocityScore < 0.4) return IssueStatus.cooling;
    return IssueStatus.steady;
  }

  /// 점수 내림차순 정렬된 새 리스트 반환.
  List<Issue> sort(List<Issue> issues, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final copy = [...issues];
    copy.sort((a, b) => _total(b, at).compareTo(_total(a, at)));
    return copy;
  }
}
