import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/identity/anon_identity.dart';
import '../../domain/models/issue.dart';
import '../../domain/models/post.dart';
import 'issue_repository.dart';

/// 사용자에게 그대로 보여줄 수 있는 오류.
/// Postgres 트리거가 올린 한국어 메시지(도배 차단 등)를 그대로 전달한다.
class HotIssueException implements Exception {
  const HotIssueException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Supabase(Postgres + Realtime) 구현.
///
/// 설계 메모
///  - `issues.ranks` 를 jsonb 로 비정규화해 뒀기 때문에 조인 없이 `.stream()` 하나로
///    카드에 필요한 모든 값이 온다. Realtime 스트림은 조인을 지원하지 않는다.
///  - 추천/반응 토글은 RPC로 넘긴다. 클라이언트가 "지금 눌린 상태인지"를 몰라도
///    서버가 원자적으로 뒤집어 주므로 경쟁 상태와 중복 추천이 원천 차단된다.
///  - 계정이 없으므로 닉네임은 매 글마다 `(uid + 방id)` 해시로 만들어 넣는다.
class SupabaseIssueRepository implements IssueRepository {
  SupabaseIssueRepository(this._client);

  final SupabaseClient _client;

  static const _imageBucket = 'post-images';

  String? get _uid => _client.auth.currentUser?.id;

  /// 활성 이슈 스트림.
  ///
  /// **필터를 서버에 둔다.** 예전에는 40건을 먼저 잘라온 뒤 클라이언트에서
  /// 아카이브를 걸렀는데, 이슈가 157건까지 쌓이자 잘라온 40건 중 31건이
  /// 아카이브라서 화면에 9건만 남았다. 관문과 필터의 순서가 뒤바뀌어 있었다.
  ///
  /// **정렬 기준이 최신순인 이유**: 이건 화면 순위가 아니라 *어느 행을 보낼지*
  /// 고르는 관문이다. 실제 순위는 클라이언트가 정렬 모드별로 HotScoreEngine 으로
  /// 계산한다. 관문에는 최신성이면 충분하고, 6시간이 지나면 아카이브로 빠지므로
  /// 오래된 것이 자리를 차지할 수 없다.
  @override
  Stream<List<Issue>> watchIssues() {
    return _client
        .from('issues')
        .stream(primaryKey: ['id'])
        .neq('status', 'archived')
        .order('last_seen_at', ascending: false)
        .limit(100)
        .map((rows) => rows.map(Issue.fromRow).toList());
  }

  @override
  Future<List<Issue>> fetchArchive() async {
    final rows = await _client
        .from('issues')
        .select()
        .eq('status', 'archived')
        .order('last_seen_at', ascending: false)
        .limit(60);

    return rows.map(Issue.fromRow).toList();
  }

  @override
  Stream<List<Post>> watchPosts(String issueId) {
    return _client
        .from('posts')
        .stream(primaryKey: ['id'])
        .eq('issue_id', issueId)
        .order('created_at', ascending: true)
        .limit(300)
        .map((rows) => rows.map(_toPost).toList());
  }

  @override
  Stream<List<Comment>> watchComments(String postId) {
    return _client
        .from('comments')
        .stream(primaryKey: ['id'])
        .eq('post_id', postId)
        .order('created_at', ascending: true)
        .limit(200)
        .map(
          (rows) => rows
              .map((row) => Comment.fromRow(row, currentUserId: _uid))
              .toList(),
        );
  }

  @override
  Future<MyInteractions> loadMyInteractions(String issueId) async {
    if (_uid == null) return const MyInteractions();

    final result = await _client.rpc<dynamic>(
      'my_room_interactions',
      params: {'p_issue_id': issueId},
    );

    if (result is Map) {
      return MyInteractions.fromJson(Map<String, dynamic>.from(result));
    }
    return const MyInteractions();
  }

  @override
  Future<void> sendPost(
    String issueId, {
    String? text,
    String? imageUrl,
  }) async {
    final uid = _requireUid();
    final body = text?.trim();
    if ((body == null || body.isEmpty) && imageUrl == null) return;

    await _guard(() async {
      await _client.from('posts').insert({
        'issue_id': issueId,
        'author_id': uid,
        'nickname': AnonIdentity.nicknameFor(userId: uid, roomId: issueId),
        'color_seed': AnonIdentity.colorSeedFor(userId: uid, roomId: issueId),
        'body': body,
        'image_path': imageUrl,
      });
    });
  }

  @override
  Future<bool> toggleLike(String issueId, String postId) async {
    _requireUid();
    return _guard(() async {
      final result = await _client.rpc<dynamic>(
        'toggle_post_like',
        params: {'p_post_id': postId},
      );
      return _asBool(result);
    });
  }

  @override
  Future<bool> toggleReaction(
    String issueId,
    String postId,
    String emoji,
  ) async {
    _requireUid();
    return _guard(() async {
      final result = await _client.rpc<dynamic>(
        'toggle_post_reaction',
        params: {'p_post_id': postId, 'p_emoji': emoji},
      );
      return _asBool(result);
    });
  }

  @override
  Future<void> addComment(String issueId, String postId, String text) async {
    final uid = _requireUid();
    final body = text.trim();
    if (body.isEmpty) return;

    await _guard(() async {
      await _client.from('comments').insert({
        'post_id': postId,
        'issue_id': issueId,
        'author_id': uid,
        'nickname': AnonIdentity.nicknameFor(userId: uid, roomId: issueId),
        'color_seed': AnonIdentity.colorSeedFor(userId: uid, roomId: issueId),
        'body': body,
      });
    });
  }

  @override
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    final uid = _requireUid();

    try {
      await _client.from('reports').insert({
        'target_type': targetType,
        'target_id': targetId,
        'reporter_id': uid,
        'reason': reason,
      });
    } on PostgrestException catch (e) {
      // 유니크 위반 = 이미 신고한 대상. 사용자에게는 성공처럼 보여도 된다.
      if (e.code == '23505') return;
      throw HotIssueException(e.message);
    }
  }

  @override
  void dispose() {
    // 스트림 구독 해제는 SDK가 관리한다. 별도로 정리할 자원이 없다.
  }

  // ── 내부 ──────────────────────────────────────────────────────────

  Post _toPost(Map<String, dynamic> row) {
    final path = row['image_path'] as String?;
    final resolved = (path == null || path.isEmpty)
        ? null
        : _client.storage.from(_imageBucket).getPublicUrl(path);

    return Post.fromRow(
      <String, dynamic>{...row, 'image_url': resolved},
      currentUserId: _uid,
    );
  }

  /// 스칼라 RPC 응답. PostgREST 버전에 따라 bool / 'true' / [true] 로 올 수 있어
  /// 세 형태를 모두 받아준다.
  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    if (value is List && value.isNotEmpty) return _asBool(value.first);
    return false;
  }

  String _requireUid() {
    final uid = _uid;
    if (uid == null) {
      throw const HotIssueException('익명 세션이 아직 준비되지 않았습니다. 새로고침해 주세요.');
    }
    return uid;
  }

  /// Postgres 예외를 사용자에게 보여줄 수 있는 메시지로 바꾼다.
  /// 레이트 리밋 트리거는 이미 한국어 메시지를 던지므로 그대로 통과시킨다.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw HotIssueException(_friendly(e));
    }
  }

  static String _friendly(PostgrestException e) {
    switch (e.code) {
      case 'P0001':
        return e.message; // 트리거/RPC가 던진 한국어 메시지
      case '23505':
        return '이미 처리된 요청입니다.';
      case '23514':
        return '입력 형식이 올바르지 않습니다.';
      case '42501':
        return '권한이 없습니다.';
      default:
        return '요청을 처리하지 못했습니다. (${e.code ?? 'unknown'})';
    }
  }
}
