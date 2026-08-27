import 'dart:convert';
import 'dart:io';

/// 이슈 한 건. 앱의 `Issue.fromRow` 가 그대로 읽을 수 있는 형태로 직렬화된다.
class IssueRecord {
  IssueRecord({
    required this.id,
    required this.keyword,
    required this.normalizedKeyword,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.summary,
    this.status = 'steady',
    this.ranks = const [],
    this.relatedKeywords = const [],
    this.sourceTitle,
    this.sourceUrl,
    this.sourceOutlet,
    this.approxTraffic,
  });

  final String id;
  final String keyword;
  final String normalizedKeyword;

  DateTime firstSeenAt;
  DateTime lastSeenAt;
  String? summary;
  String status;

  /// `[{source, rank, previous_rank, observed_at}]`
  List<Map<String, dynamic>> ranks;
  List<String> relatedKeywords;

  /// 원문 기사 — 복제하지 않고 링크만 건다
  String? sourceTitle;
  String? sourceUrl;
  String? sourceOutlet;

  /// 구글 트렌드가 주는 대략적 검색량 (`2000+`)
  String? approxTraffic;

  /// 참여 지표는 스토어가 계산해서 채운다
  int postsCount = 0;
  int commentsCount = 0;
  int likesCount = 0;
  int reactionsCount = 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'keyword': keyword,
        'normalized_keyword': normalizedKeyword,
        'summary': summary,
        'status': status,
        'ranks': ranks,
        'related_keywords': relatedKeywords,
        'source_title': sourceTitle,
        'source_url': sourceUrl,
        'source_outlet': sourceOutlet,
        'approx_traffic': approxTraffic,
        'posts_count': postsCount,
        'comments_count': commentsCount,
        'likes_count': likesCount,
        'reactions_count': reactionsCount,
        'live_users': 0,
        'first_seen_at': firstSeenAt.toUtc().toIso8601String(),
        'last_seen_at': lastSeenAt.toUtc().toIso8601String(),
      };

  static IssueRecord fromJson(Map<String, dynamic> j) {
    final r = IssueRecord(
      id: j['id'] as String,
      keyword: j['keyword'] as String,
      normalizedKeyword: j['normalized_keyword'] as String? ?? '',
      firstSeenAt: DateTime.parse(j['first_seen_at'] as String),
      lastSeenAt: DateTime.parse(j['last_seen_at'] as String),
      summary: j['summary'] as String?,
      status: j['status'] as String? ?? 'steady',
      ranks: ((j['ranks'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      relatedKeywords:
          ((j['related_keywords'] as List?) ?? const []).cast<String>(),
      sourceTitle: j['source_title'] as String?,
      sourceUrl: j['source_url'] as String?,
      sourceOutlet: j['source_outlet'] as String?,
      approxTraffic: j['approx_traffic'] as String?,
    );
    return r;
  }
}

class PostRecord {
  PostRecord({
    required this.id,
    required this.issueId,
    required this.authorId,
    required this.nickname,
    required this.colorSeed,
    required this.createdAt,
    this.body,
    this.imageUrl,
    this.isPinned = false,
    this.isHidden = false,
  });

  final String id;
  final String issueId;
  final String authorId;
  final String nickname;
  final int colorSeed;
  final DateTime createdAt;
  final String? body;
  final String? imageUrl;
  bool isPinned;
  bool isHidden;
  int reportCount = 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'issue_id': issueId,
        'author_id': authorId,
        'nickname': nickname,
        'color_seed': colorSeed,
        'body': body,
        'image_url': imageUrl,
        'is_pinned': isPinned,
        'is_hidden': isHidden,
        'report_count': reportCount,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  static PostRecord fromJson(Map<String, dynamic> j) => PostRecord(
        id: j['id'] as String,
        issueId: j['issue_id'] as String,
        authorId: j['author_id'] as String,
        nickname: j['nickname'] as String,
        colorSeed: (j['color_seed'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(j['created_at'] as String),
        body: j['body'] as String?,
        imageUrl: j['image_url'] as String?,
        isPinned: j['is_pinned'] as bool? ?? false,
        isHidden: j['is_hidden'] as bool? ?? false,
      )..reportCount = (j['report_count'] as num?)?.toInt() ?? 0;
}

class CommentRecord {
  CommentRecord({
    required this.id,
    required this.postId,
    required this.issueId,
    required this.authorId,
    required this.nickname,
    required this.colorSeed,
    required this.body,
    required this.createdAt,
    this.isHidden = false,
  });

  final String id;
  final String postId;
  final String issueId;
  final String authorId;
  final String nickname;
  final int colorSeed;
  final String body;
  final DateTime createdAt;
  bool isHidden;

  Map<String, dynamic> toJson() => {
        'id': id,
        'post_id': postId,
        'issue_id': issueId,
        'author_id': authorId,
        'nickname': nickname,
        'color_seed': colorSeed,
        'body': body,
        'is_hidden': isHidden,
        'likes_count': 0,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  static CommentRecord fromJson(Map<String, dynamic> j) => CommentRecord(
        id: j['id'] as String,
        postId: j['post_id'] as String,
        issueId: j['issue_id'] as String,
        authorId: j['author_id'] as String,
        nickname: j['nickname'] as String,
        colorSeed: (j['color_seed'] as num?)?.toInt() ?? 0,
        body: j['body'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        isHidden: j['is_hidden'] as bool? ?? false,
      );
}

/// 인메모리 저장소 + JSON 파일 영속화.
///
/// Supabase 를 쓰지 않고도 앱이 완전히 동작하게 하는 게 목적이다.
/// 스키마는 Supabase 쪽과 같은 모양으로 맞춰서, 나중에 백엔드를 바꿔도
/// 클라이언트가 달라질 게 없게 한다.
class Store {
  Store(this.file);

  final File file;

  final Map<String, IssueRecord> issues = {};
  final Map<String, List<PostRecord>> postsByIssue = {};
  final Map<String, List<CommentRecord>> commentsByPost = {};

  /// postId -> 추천한 익명 ID들
  final Map<String, Set<String>> likes = {};

  /// postId -> emoji -> 반응한 익명 ID들
  final Map<String, Map<String, Set<String>>> reactions = {};

  /// 도배 차단용. anonId -> 최근 작성 시각들
  final Map<String, List<DateTime>> _recentPosts = {};

  // ── 참여 지표 ───────────────────────────────────────────────────

  /// 이슈의 카운터를 실제 데이터에서 다시 센다.
  /// (Supabase 는 트리거가 하는 일을 여기서는 직접 한다)
  void recount(String issueId) {
    final issue = issues[issueId];
    if (issue == null) return;

    final posts = postsByIssue[issueId] ?? const <PostRecord>[];
    var comments = 0;
    var likeCount = 0;
    var reactionCount = 0;

    for (final post in posts) {
      comments += (commentsByPost[post.id] ?? const []).length;
      likeCount += (likes[post.id] ?? const {}).length;
      for (final users in (reactions[post.id] ?? const {}).values) {
        reactionCount += users.length;
      }
    }

    issue.postsCount = posts.length;
    issue.commentsCount = comments;
    issue.likesCount = likeCount;
    issue.reactionsCount = reactionCount;
  }

  void recountAll() {
    for (final id in issues.keys) {
      recount(id);
    }
  }

  // ── 도배 차단 ───────────────────────────────────────────────────

  /// Supabase 의 `enforce_post_rate_limit` 트리거와 같은 규칙(10초 3건)을 쓴다.
  /// 목/실서버/수집기가 서로 다르게 동작하면 한쪽에서 한 테스트가 거짓 안심이 된다.
  bool allowPost(String anonId) {
    final now = DateTime.now();
    final window = now.subtract(const Duration(seconds: 10));
    final recent =
        (_recentPosts[anonId] ?? []).where((t) => t.isAfter(window)).toList();

    if (recent.length >= 3) {
      _recentPosts[anonId] = recent;
      return false;
    }

    recent.add(now);
    _recentPosts[anonId] = recent;
    return true;
  }

  // ── 영속화 ─────────────────────────────────────────────────────

  Future<void> load() async {
    if (!await file.exists()) return;

    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

      for (final j in (raw['issues'] as List? ?? const [])) {
        final rec = IssueRecord.fromJson(Map<String, dynamic>.from(j as Map));
        issues[rec.id] = rec;
      }
      for (final j in (raw['posts'] as List? ?? const [])) {
        final rec = PostRecord.fromJson(Map<String, dynamic>.from(j as Map));
        postsByIssue.putIfAbsent(rec.issueId, () => []).add(rec);
      }
      for (final j in (raw['comments'] as List? ?? const [])) {
        final rec = CommentRecord.fromJson(Map<String, dynamic>.from(j as Map));
        commentsByPost.putIfAbsent(rec.postId, () => []).add(rec);
      }
      (raw['likes'] as Map? ?? const {}).forEach((k, v) {
        likes['$k'] = (v as List).map((e) => '$e').toSet();
      });
      (raw['reactions'] as Map? ?? const {}).forEach((postId, byEmoji) {
        final map = <String, Set<String>>{};
        (byEmoji as Map).forEach((emoji, users) {
          map['$emoji'] = (users as List).map((e) => '$e').toSet();
        });
        reactions['$postId'] = map;
      });

      recountAll();
    } catch (error) {
      stderr.writeln('[store] 상태 파일을 읽지 못해 빈 상태로 시작합니다: $error');
    }
  }

  Future<void> save() async {
    final payload = {
      'issues': issues.values.map((e) => e.toJson()).toList(),
      'posts':
          postsByIssue.values.expand((e) => e).map((e) => e.toJson()).toList(),
      'comments': commentsByPost.values
          .expand((e) => e)
          .map((e) => e.toJson())
          .toList(),
      'likes': likes.map((k, v) => MapEntry(k, v.toList())),
      'reactions': reactions.map(
        (k, v) => MapEntry(k, v.map((e, users) => MapEntry(e, users.toList()))),
      ),
    };

    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload));
  }
}
