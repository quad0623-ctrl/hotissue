import 'dart:async';
import 'dart:math';

import '../../domain/models/issue.dart';
import '../../domain/models/post.dart';
import '../mock/mock_feed.dart';
import 'issue_repository.dart';

/// 인메모리 목 구현. 3초마다 순위와 참여 지표를 흔들어 실시간처럼 보이게 한다.
///
/// Supabase 프로젝트 없이도 앱 전체를 돌려볼 수 있게 하는 게 목적이다.
/// 실데이터가 붙으면 통째로 제거한다 → delete_plan.md DEL-01
class MockIssueRepository implements IssueRepository {
  MockIssueRepository() {
    _issues = _feed.generateIssues();
    _ticker = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
  }

  final MockFeed _feed = MockFeed();
  final Random _rnd = Random();

  late List<Issue> _issues;
  late final Timer _ticker;

  final _issuesController = StreamController<List<Issue>>.broadcast();

  final Map<String, List<Post>> _posts = {};
  final Map<String, StreamController<List<Post>>> _postControllers = {};

  /// postId -> 댓글
  final Map<String, List<Comment>> _comments = {};
  final Map<String, StreamController<List<Comment>>> _commentControllers = {};

  /// 내가 누른 것들 (방 단위)
  final Map<String, MyInteractions> _mine = {};

  /// 구독 즉시 현재 상태를 한 번 흘리고, 이후 갱신을 이어붙인다.
  /// (broadcast 컨트롤러의 onListen 안에서 add 하면 첫 이벤트가 유실될 수 있어서)
  @override
  Stream<List<Issue>> watchIssues() async* {
    yield _issues;
    yield* _issuesController.stream;
  }

  @override
  Future<List<Issue>> fetchArchive() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final now = DateTime.now();

    return MockFeed(seed: 1234)
        .generateIssues(count: 20, idPrefix: 'past')
        .map((issue) {
      return issue.copyWith(
        status: IssueStatus.archived,
        lastSeenAt: now.subtract(Duration(hours: 6 + _rnd.nextInt(240))),
      );
    }).toList();
  }

  @override
  Stream<List<Post>> watchPosts(String issueId) async* {
    _ensureRoom(issueId);

    final controller = _postControllers.putIfAbsent(
      issueId,
      () => StreamController<List<Post>>.broadcast(),
    );

    yield List<Post>.unmodifiable(_posts[issueId]!);
    yield* controller.stream;
  }

  @override
  Stream<List<Comment>> watchComments(String postId) async* {
    final controller = _commentControllers.putIfAbsent(
      postId,
      () => StreamController<List<Comment>>.broadcast(),
    );

    yield List<Comment>.unmodifiable(_comments[postId] ?? const []);
    yield* controller.stream;
  }

  @override
  Future<MyInteractions> loadMyInteractions(String issueId) async =>
      _mine[issueId] ?? const MyInteractions();

  @override
  Future<void> sendPost(
    String issueId, {
    String? text,
    String? imageUrl,
  }) async {
    if ((text == null || text.trim().isEmpty) && imageUrl == null) return;

    _ensureRoom(issueId);
    _posts[issueId]!.add(
      Post(
        id: '${issueId}_me_${DateTime.now().microsecondsSinceEpoch}',
        issueId: issueId,
        author: MockFeed.me,
        createdAt: DateTime.now(),
        text: text?.trim(),
        imageUrl: imageUrl,
      ),
    );

    _bumpStats(issueId, posts: 1);
    _emitPosts(issueId);
  }

  @override
  Future<bool> toggleLike(String issueId, String postId) async {
    final mine = _mine[issueId] ?? const MyInteractions();
    final on = !mine.likes(postId);
    _mine[issueId] = mine.withLike(postId, on);

    _updatePost(issueId, postId, (p) {
      return p.copyWith(likes: (p.likes + (on ? 1 : -1)).clamp(0, 1 << 30));
    });

    _bumpStats(issueId, likes: on ? 1 : -1);
    _emitPosts(issueId);
    return on;
  }

  @override
  Future<bool> toggleReaction(
    String issueId,
    String postId,
    String emoji,
  ) async {
    final mine = _mine[issueId] ?? const MyInteractions();
    final on = !mine.reacted(postId, emoji);
    _mine[issueId] = mine.withReaction(postId, emoji, on);

    _updatePost(issueId, postId, (p) {
      final next = Map<String, int>.from(p.reactions);
      final value = (next[emoji] ?? 0) + (on ? 1 : -1);
      if (value <= 0) {
        next.remove(emoji);
      } else {
        next[emoji] = value;
      }
      return p.copyWith(reactions: next);
    });

    _bumpStats(issueId, reactions: on ? 1 : -1);
    _emitPosts(issueId);
    return on;
  }

  @override
  Future<void> addComment(String issueId, String postId, String text) async {
    if (text.trim().isEmpty) return;

    final list = _comments.putIfAbsent(postId, () => []);
    list.add(
      Comment(
        id: '${postId}_c_${DateTime.now().microsecondsSinceEpoch}',
        postId: postId,
        author: MockFeed.me,
        text: text.trim(),
        createdAt: DateTime.now(),
      ),
    );

    _updatePost(issueId, postId, (p) {
      return p.copyWith(commentCount: p.commentCount + 1);
    });

    _bumpStats(issueId, comments: 1);
    _emitComments(postId);
    _emitPosts(issueId);
  }

  @override
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    // 목에서는 접수만 흉내낸다.
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  @override
  void dispose() {
    _ticker.cancel();
    _issuesController.close();
    for (final c in _postControllers.values) {
      c.close();
    }
    for (final c in _commentControllers.values) {
      c.close();
    }
  }

  // ── 내부 ──────────────────────────────────────────────────────────

  /// 방을 처음 열 때 글과 댓글을 함께 생성한다.
  void _ensureRoom(String issueId) {
    if (_posts.containsKey(issueId)) return;

    final posts = _feed.generatePosts(issueId);
    _posts[issueId] = posts;

    for (final post in posts) {
      _comments[post.id] = _feed.generateComments(post.id, post.commentCount);
    }
  }

  /// 실시간 수집기를 흉내: 순위가 조금씩 움직이고 참여 지표가 늘어난다.
  void _tick() {
    final now = DateTime.now();

    _issues = _issues.map((issue) {
      final shifted = issue.ranks.map((r) {
        final next = (r.rank + _rnd.nextInt(3) - 1).clamp(1, 20);
        return SourceRank(
          source: r.source,
          rank: next,
          previousRank: r.rank,
          observedAt: now,
        );
      }).toList();

      return issue.copyWith(
        ranks: shifted,
        lastSeenAt: now,
        stats: issue.stats.copyWith(
          posts: issue.stats.posts + _rnd.nextInt(2),
          comments: issue.stats.comments + _rnd.nextInt(3),
          reactions: issue.stats.reactions + _rnd.nextInt(4),
          liveUsers:
              (issue.stats.liveUsers + _rnd.nextInt(7) - 3).clamp(0, 999),
        ),
      );
    }).toList();

    if (!_issuesController.isClosed) _issuesController.add(_issues);
  }

  void _updatePost(String issueId, String postId, Post Function(Post) apply) {
    final list = _posts[issueId];
    if (list == null) return;

    final index = list.indexWhere((p) => p.id == postId);
    if (index == -1) return;

    list[index] = apply(list[index]);
  }

  void _bumpStats(
    String issueId, {
    int posts = 0,
    int comments = 0,
    int likes = 0,
    int reactions = 0,
  }) {
    _issues = _issues.map((issue) {
      if (issue.id != issueId) return issue;
      return issue.copyWith(
        stats: issue.stats.copyWith(
          posts: (issue.stats.posts + posts).clamp(0, 1 << 30),
          comments: (issue.stats.comments + comments).clamp(0, 1 << 30),
          likes: (issue.stats.likes + likes).clamp(0, 1 << 30),
          reactions: (issue.stats.reactions + reactions).clamp(0, 1 << 30),
        ),
      );
    }).toList();

    if (!_issuesController.isClosed) _issuesController.add(_issues);
  }

  void _emitPosts(String issueId) {
    final controller = _postControllers[issueId];
    if (controller == null || controller.isClosed) return;
    controller.add(List<Post>.unmodifiable(_posts[issueId] ?? const []));
  }

  void _emitComments(String postId) {
    final controller = _commentControllers[postId];
    if (controller == null || controller.isClosed) return;
    controller.add(List<Comment>.unmodifiable(_comments[postId] ?? const []));
  }
}
