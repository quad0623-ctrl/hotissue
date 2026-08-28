import 'json_utils.dart';
import 'trend_source.dart';

/// 특정 소스에서 관측된 키워드의 순위 스냅샷.
class SourceRank {
  const SourceRank({
    required this.source,
    required this.rank,
    required this.observedAt,
    this.previousRank,
  });

  final TrendSource source;

  /// 1부터 시작. 낮을수록 상위.
  final int rank;

  /// 직전 스냅샷의 순위. 신규 진입이면 null.
  final int? previousRank;

  final DateTime observedAt;

  /// 순위 상승폭 (양수 = 상승). 신규 진입은 최대 상승으로 간주.
  int get delta => previousRank == null ? 99 : previousRank! - rank;

  bool get isNew => previousRank == null;

  /// `issues.ranks` jsonb 배열의 한 원소를 파싱한다.
  factory SourceRank.fromJson(Map<String, dynamic> json) {
    final observed = json['observed_at'];
    return SourceRank(
      source: TrendSource.fromDb(json['source'] as String?),
      rank: (json['rank'] as num?)?.toInt() ?? 99,
      previousRank: (json['previous_rank'] as num?)?.toInt(),
      observedAt: observed is String
          ? DateTime.parse(observed).toLocal()
          : DateTime.now(),
    );
  }
}

/// 이슈방의 자체 참여 지표. 외부 순위와 별개로 우리 서비스 안의 열기를 잰다.
class RoomStats {
  const RoomStats({
    this.posts = 0,
    this.comments = 0,
    this.likes = 0,
    this.reactions = 0,
    this.liveUsers = 0,
  });

  final int posts;
  final int comments;
  final int likes;
  final int reactions;
  final int liveUsers;

  RoomStats copyWith({
    int? posts,
    int? comments,
    int? likes,
    int? reactions,
    int? liveUsers,
  }) {
    return RoomStats(
      posts: posts ?? this.posts,
      comments: comments ?? this.comments,
      likes: likes ?? this.likes,
      reactions: reactions ?? this.reactions,
      liveUsers: liveUsers ?? this.liveUsers,
    );
  }
}

/// 이슈 생애주기.
enum IssueStatus {
  rising('급상승'),
  hot('과열'),
  steady('유지'),
  cooling('식는 중'),
  archived('아카이브');

  const IssueStatus(this.label);
  final String label;

  static IssueStatus fromDb(String? name) {
    for (final s in IssueStatus.values) {
      if (s.name == name) return s;
    }
    return IssueStatus.steady;
  }
}

/// 하나의 이슈 = 하나의 키워드 = 하나의 채팅방.
class Issue {
  const Issue({
    required this.id,
    required this.keyword,
    required this.ranks,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.stats = const RoomStats(),
    this.status = IssueStatus.steady,
    this.summary,
    this.relatedKeywords = const [],
    this.sourceTitle,
    this.sourceUrl,
    this.sourceOutlet,
    this.approxTraffic,
    this.imageUrl,
  });

  final String id;
  final String keyword;
  final List<SourceRank> ranks;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final RoomStats stats;
  final IssueStatus status;

  /// 이슈 한 줄 요약. Phase 3에서 LLM으로 자동 생성.
  final String? summary;

  final List<String> relatedKeywords;

  /// 이 이슈를 촉발한 원문 기사. **본문을 복제하지 않고 링크만 건다.**
  /// 구글 트렌드 피드가 함께 주는 값이라 우리가 요약을 지어낼 필요가 없다.
  final String? sourceTitle;
  final String? sourceUrl;
  final String? sourceOutlet;

  /// 구글 트렌드가 주는 대략적 검색량 (`2000+`)
  final String? approxTraffic;

  /// 기사 썸네일. 이미지를 복제하지 않고 원본 URL 만 들고 있는다.
  final String? imageUrl;

  Duration get age => DateTime.now().difference(firstSeenAt);

  /// Supabase `issues` 행 → 도메인 모델.
  ///
  /// ranks 를 jsonb 컬럼으로 비정규화해 둔 덕분에 조인 없이 한 줄로 복원된다.
  /// (`.stream()` 은 조인을 지원하지 않으므로 이게 실시간 구독의 전제 조건이다)
  factory Issue.fromRow(Map<String, dynamic> row) {
    final rawRanks = row['ranks'];
    final ranks = rawRanks is List
        ? rawRanks
            .whereType<Map<String, dynamic>>()
            .map(SourceRank.fromJson)
            .toList()
        : <SourceRank>[];

    return Issue(
      id: row['id'] as String,
      keyword: row['keyword'] as String? ?? '',
      ranks: ranks,
      firstSeenAt: parseTime(row['first_seen_at']),
      lastSeenAt: parseTime(row['last_seen_at']),
      status: IssueStatus.fromDb(row['status'] as String?),
      summary: row['summary'] as String?,
      relatedKeywords: parseStringList(row['related_keywords']),
      sourceTitle: row['source_title'] as String?,
      sourceUrl: row['source_url'] as String?,
      sourceOutlet: row['source_outlet'] as String?,
      approxTraffic: row['approx_traffic'] as String?,
      imageUrl: row['image_url'] as String?,
      stats: RoomStats(
        posts: parseInt(row['posts_count']),
        comments: parseInt(row['comments_count']),
        likes: parseInt(row['likes_count']),
        reactions: parseInt(row['reactions_count']),
        liveUsers: parseInt(row['live_users']),
      ),
    );
  }

  Issue copyWith({
    List<SourceRank>? ranks,
    DateTime? lastSeenAt,
    RoomStats? stats,
    IssueStatus? status,
    String? summary,
  }) {
    return Issue(
      id: id,
      keyword: keyword,
      ranks: ranks ?? this.ranks,
      firstSeenAt: firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      stats: stats ?? this.stats,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      relatedKeywords: relatedKeywords,
      sourceTitle: sourceTitle,
      sourceUrl: sourceUrl,
      sourceOutlet: sourceOutlet,
      approxTraffic: approxTraffic,
      imageUrl: imageUrl,
    );
  }
}
