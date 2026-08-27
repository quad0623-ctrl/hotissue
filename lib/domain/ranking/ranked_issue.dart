import '../models/issue.dart';
import 'hot_score.dart';

/// 정렬 모드. 사용자가 직접 고를 수 있게 해서
/// "왜 이 순서냐"는 불만을 선택권으로 바꾼다.
enum RankingMode {
  balanced('균형', '순위·상승세·참여도를 고루 반영', HotScoreWeights.balanced),
  breaking('속보', '지금 막 튀어오르는 것 위주', HotScoreWeights.breaking),
  discussion('토론', '우리 방이 뜨거운 것 위주', HotScoreWeights.discussion);

  const RankingMode(this.label, this.description, this.weights);

  final String label;
  final String description;
  final HotScoreWeights weights;
}

/// 정렬 결과 한 줄. 순위와 근거를 함께 들고 다닌다.
class RankedIssue {
  const RankedIssue({
    required this.issue,
    required this.position,
    required this.breakdown,
    required this.status,
    this.previousPosition,
  });

  final Issue issue;

  /// 1부터 시작하는 우리 서비스의 순위
  final int position;

  /// 직전 갱신에서의 우리 순위 (없으면 신규)
  final int? previousPosition;

  final HotScoreBreakdown breakdown;
  final IssueStatus status;

  int? get positionDelta =>
      previousPosition == null ? null : previousPosition! - position;

  bool get isNew => previousPosition == null;
}

/// 순위 계산 + 직전 순위 기억. Provider에 싱글턴으로 물려서 상태를 유지한다.
class RankingService {
  final Map<String, int> _previousPositions = {};

  List<RankedIssue> rank(List<Issue> issues, RankingMode mode) {
    final engine = HotScoreEngine(weights: mode.weights);
    final now = DateTime.now();

    final scored = issues
        .map((i) => (issue: i, breakdown: engine.score(i, now: now)))
        .toList()
      ..sort((a, b) => b.breakdown.total.compareTo(a.breakdown.total));

    final result = <RankedIssue>[];
    for (var i = 0; i < scored.length; i++) {
      final entry = scored[i];
      result.add(
        RankedIssue(
          issue: entry.issue,
          position: i + 1,
          previousPosition: _previousPositions[entry.issue.id],
          breakdown: entry.breakdown,
          status: engine.classify(entry.issue, now: now),
        ),
      );
    }

    // 다음 계산을 위해 현재 순위를 기억
    for (final r in result) {
      _previousPositions[r.issue.id] = r.position;
    }

    return result;
  }

  /// 정렬 모드를 바꾸면 이전 순위 비교가 무의미해지므로 초기화한다.
  void reset() => _previousPositions.clear();
}
