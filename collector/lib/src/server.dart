import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'collector.dart';
import 'source.dart';
import 'store.dart';

/// 수집기가 겸하는 미니 백엔드.
///
/// Supabase 없이도 앱이 완전히 동작하게 하는 게 목적이다.
/// 엔드포인트 응답 모양은 Supabase 테이블 행과 같게 맞췄다 —
/// 클라이언트가 백엔드를 바꿔도 파싱 코드가 그대로여야 하기 때문이다.
///
/// 익명 식별자는 `X-Anon-Id` 헤더로 받는다. 계정도, 세션도, 쿠키도 없다.
class CollectorServer {
  CollectorServer({required this.store, required this.collector});

  final Store store;
  final Collector collector;

  static const _maxBody = 500;
  static const _maxComment = 300;
  static const _allowedEmojis = {'🔥', '😮', '😡', '😂', '😢', '🤔'};

  final _random = Random();

  Handler get handler => const Pipeline()
      .addMiddleware(_cors())
      .addMiddleware(logRequests())
      .addHandler(_router.call);

  Router get _router {
    final router = Router()
      ..get('/api/health', _health)
      ..get('/api/sources', _sources)
      ..get('/api/issues', _issues)
      ..get('/api/archive', _archive)
      ..get('/api/issues/<id>/posts', _posts)
      ..post('/api/issues/<id>/posts', _createPost)
      ..get('/api/issues/<id>/me', _myInteractions)
      ..get('/api/posts/<id>/comments', _comments)
      ..post('/api/posts/<id>/comments', _createComment)
      ..post('/api/posts/<id>/like', _toggleLike)
      ..post('/api/posts/<id>/reactions', _toggleReaction)
      ..post('/api/reports', _report);
    return router;
  }

  // ── 조회 ────────────────────────────────────────────────────────

  Response _health(Request _) => _json({
        'ok': true,
        'last_run_at': collector.lastRunAt?.toUtc().toIso8601String(),
        'last_error': collector.lastError,
        'issues': store.issues.length,
        'sources': collector.sourceStatus,
      });

  Response _sources(Request _) => _json({
        'sources': [
          for (final s in kOutlets)
            {
              'id': s.id,
              'label': s.label,
              'code': s.code,
              'weight': s.weight,
              'kind': s.kind.name,
            },
        ],
      });

  Response _issues(Request _) {
    final live = store.issues.values
        .where((i) => i.status != 'archived')
        .map((i) => i.toJson())
        .toList();
    return _json({'issues': live});
  }

  Response _archive(Request _) {
    final archived = store.issues.values
        .where((i) => i.status == 'archived')
        .toList()
      ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));

    return _json({
      'issues': archived.take(60).map((i) => i.toJson()).toList(),
    });
  }

  Response _posts(Request request, String id) {
    final posts = (store.postsByIssue[id] ?? const <PostRecord>[])
        .map(_postJson)
        .toList();
    return _json({'posts': posts});
  }

  Response _comments(Request request, String id) {
    final comments = (store.commentsByPost[id] ?? const <CommentRecord>[])
        .map((c) => c.toJson())
        .toList();
    return _json({'comments': comments});
  }

  Response _myInteractions(Request request, String id) {
    final anonId = _anonId(request);
    if (anonId == null) return _json({'likes': [], 'reactions': {}});

    final likedIds = <String>[];
    final myReactions = <String, List<String>>{};

    for (final post in store.postsByIssue[id] ?? const <PostRecord>[]) {
      if ((store.likes[post.id] ?? const {}).contains(anonId)) {
        likedIds.add(post.id);
      }
      final mine = <String>[];
      (store.reactions[post.id] ?? const {}).forEach((emoji, users) {
        if (users.contains(anonId)) mine.add(emoji);
      });
      if (mine.isNotEmpty) myReactions[post.id] = mine;
    }

    return _json({'likes': likedIds, 'reactions': myReactions});
  }

  // ── 쓰기 ────────────────────────────────────────────────────────

  Future<Response> _createPost(Request request, String id) async {
    final anonId = _anonId(request);
    if (anonId == null) return _error(401, '익명 세션이 없습니다.');
    if (!store.issues.containsKey(id)) return _error(404, '이슈를 찾을 수 없습니다.');

    final body = await _body(request);
    final text = (body['text'] as String?)?.trim();
    final imageUrl = body['image_url'] as String?;

    if ((text == null || text.isEmpty) && imageUrl == null) {
      return _error(400, '내용이 비어 있습니다.');
    }
    if (text != null && text.length > _maxBody) {
      return _error(400, '본문은 $_maxBody자를 넘을 수 없습니다.');
    }

    // Supabase 의 enforce_post_rate_limit 트리거와 같은 규칙·같은 메시지.
    if (!store.allowPost(anonId)) {
      return _error(429, '너무 빠르게 작성하고 있습니다. 잠시 후 다시 시도해주세요.');
    }

    final post = PostRecord(
      id: _id('post'),
      issueId: id,
      authorId: anonId,
      nickname: (body['nickname'] as String?) ?? '익명',
      colorSeed: (body['color_seed'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.now(),
      body: text,
      imageUrl: imageUrl,
    );

    store.postsByIssue.putIfAbsent(id, () => []).add(post);
    store.recount(id);
    await store.save();

    return _json(_postJson(post), status: 201);
  }

  Future<Response> _createComment(Request request, String id) async {
    final anonId = _anonId(request);
    if (anonId == null) return _error(401, '익명 세션이 없습니다.');

    final post = _findPost(id);
    if (post == null) return _error(404, '글을 찾을 수 없습니다.');

    final body = await _body(request);
    final text = (body['text'] as String?)?.trim();
    if (text == null || text.isEmpty) return _error(400, '내용이 비어 있습니다.');
    if (text.length > _maxComment) {
      return _error(400, '댓글은 $_maxComment자를 넘을 수 없습니다.');
    }

    final comment = CommentRecord(
      id: _id('cmt'),
      postId: id,
      issueId: post.issueId,
      authorId: anonId,
      nickname: (body['nickname'] as String?) ?? '익명',
      colorSeed: (body['color_seed'] as num?)?.toInt() ?? 0,
      body: text,
      createdAt: DateTime.now(),
    );

    store.commentsByPost.putIfAbsent(id, () => []).add(comment);
    store.recount(post.issueId);
    await store.save();

    return _json(comment.toJson(), status: 201);
  }

  Future<Response> _toggleLike(Request request, String id) async {
    final anonId = _anonId(request);
    if (anonId == null) return _error(401, '익명 세션이 없습니다.');

    final post = _findPost(id);
    if (post == null) return _error(404, '글을 찾을 수 없습니다.');

    // add() 는 새로 넣었을 때만 true. false 면 이미 있던 것이므로 토글해서 뺀다.
    final users = store.likes.putIfAbsent(id, () => <String>{});
    final liked = users.add(anonId);
    if (!liked) users.remove(anonId);

    store.recount(post.issueId);
    await store.save();

    return _json({'liked': liked});
  }

  Future<Response> _toggleReaction(Request request, String id) async {
    final anonId = _anonId(request);
    if (anonId == null) return _error(401, '익명 세션이 없습니다.');

    final post = _findPost(id);
    if (post == null) return _error(404, '글을 찾을 수 없습니다.');

    final body = await _body(request);
    final emoji = body['emoji'] as String?;
    if (emoji == null || !_allowedEmojis.contains(emoji)) {
      return _error(400, '허용되지 않은 이모지입니다.');
    }

    final byEmoji = store.reactions.putIfAbsent(id, () => {});
    final users = byEmoji.putIfAbsent(emoji, () => <String>{});

    final on = users.add(anonId);
    if (!on) users.remove(anonId);
    if (users.isEmpty) byEmoji.remove(emoji);

    store.recount(post.issueId);
    await store.save();

    return _json({'on': on});
  }

  Future<Response> _report(Request request) async {
    final anonId = _anonId(request);
    if (anonId == null) return _error(401, '익명 세션이 없습니다.');

    final body = await _body(request);
    final targetType = body['target_type'] as String?;
    final targetId = body['target_id'] as String?;
    if (targetType == null || targetId == null) {
      return _error(400, '신고 대상이 지정되지 않았습니다.');
    }

    if (targetType == 'post') {
      final post = _findPost(targetId);
      if (post != null) {
        post.reportCount++;
        // Supabase 의 on_report_created 트리거와 같은 임계치
        if (post.reportCount >= 5) post.isHidden = true;
        await store.save();
      }
    }

    return _json({'ok': true});
  }

  // ── 내부 ────────────────────────────────────────────────────────

  Map<String, dynamic> _postJson(PostRecord post) {
    final reactionCounts = <String, int>{};
    (store.reactions[post.id] ?? const {}).forEach((emoji, users) {
      if (users.isNotEmpty) reactionCounts[emoji] = users.length;
    });

    return {
      ...post.toJson(),
      'likes_count': (store.likes[post.id] ?? const {}).length,
      'comments_count': (store.commentsByPost[post.id] ?? const []).length,
      'reaction_counts': reactionCounts,
    };
  }

  PostRecord? _findPost(String postId) {
    for (final posts in store.postsByIssue.values) {
      for (final post in posts) {
        if (post.id == postId) return post;
      }
    }
    return null;
  }

  String? _anonId(Request request) {
    final value = request.headers['x-anon-id']?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<Map<String, dynamic>> _body(Request request) async {
    try {
      final raw = await request.readAsString();
      if (raw.isEmpty) return {};
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  String _id(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 16)}';

  Response _json(Object payload, {int status = 200}) => Response(
        status,
        body: jsonEncode(payload),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Response _error(int status, String message) =>
      _json({'error': message}, status: status);
}

/// 로컬 개발용 CORS. 앱이 :8080, 수집기가 :8787 이라 브라우저가 교차 출처로 본다.
Middleware _cors() {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-Anon-Id',
    'Access-Control-Max-Age': '86400',
  };

  return createMiddleware(
    requestHandler: (request) =>
        request.method == 'OPTIONS' ? Response.ok('', headers: headers) : null,
    responseHandler: (response) => response.change(headers: headers),
  );
}
