import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/identity/anon_identity.dart';
import '../../domain/models/issue.dart';
import '../../domain/models/post.dart';
import 'issue_repository.dart';

/// 사용자에게 그대로 보여줄 수 있는 오류.
class CollectorException implements Exception {
  const CollectorException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 로컬 수집기(`collector/`)를 백엔드로 쓰는 구현.
///
/// Supabase 프로젝트 없이도 **실제 데이터로** 앱을 돌리기 위한 경로다.
/// 수집기가 공식 RSS 피드에서 실시간 이슈를 모으고, 글·댓글·반응까지 보관한다.
///
/// 실시간성은 폴링으로 만든다. Realtime 소켓을 쓰지 않는 이유:
///  - 원본 소스(구글 트렌드)가 분 단위로 갱신되므로 순위는 20초 폴링이면 충분하다
///  - 방 대화는 4초 폴링이면 체감상 실시간과 구분되지 않는다
///  - 소켓 재연결·백오프를 직접 구현하는 비용이 이득보다 크다
/// 트래픽이 커지면 SSE 로 바꾼다.
class HttpIssueRepository implements IssueRepository {
  HttpIssueRepository({
    required this.baseUrl,
    required this.anonId,
    http.Client? client,
    this.issuesInterval = const Duration(seconds: 20),
    this.postsInterval = const Duration(seconds: 4),
    this.commentsInterval = const Duration(seconds: 6),
  }) : _client = client ?? http.Client();

  /// 예: `http://localhost:8787`
  final String baseUrl;

  /// 브라우저마다 하나씩 생성해 보관하는 익명 식별자.
  /// 계정이 아니다 — 자기 글 구분과 1인 1추천에만 쓴다.
  final String anonId;

  final http.Client _client;
  final Duration issuesInterval;
  final Duration postsInterval;
  final Duration commentsInterval;

  bool _disposed = false;

  Map<String, String> get _headers => {
        'X-Anon-Id': anonId,
        'Content-Type': 'application/json; charset=utf-8',
      };

  // ── 조회 ────────────────────────────────────────────────────────

  @override
  Stream<List<Issue>> watchIssues() => _poll(issuesInterval, () async {
        final body = await _get('/api/issues');
        return _issueList(body['issues']);
      });

  @override
  Future<List<Issue>> fetchArchive() async {
    final body = await _get('/api/archive');
    return _issueList(body['issues']);
  }

  @override
  Stream<List<Post>> watchPosts(String issueId) =>
      _poll(postsInterval, () async {
        final body = await _get('/api/issues/$issueId/posts');
        return ((body['posts'] as List?) ?? const [])
            .whereType<Map>()
            .map(_toPost)
            .toList();
      });

  @override
  Stream<List<Comment>> watchComments(String postId) =>
      _poll(commentsInterval, () async {
        final body = await _get('/api/posts/$postId/comments');
        return ((body['comments'] as List?) ?? const [])
            .whereType<Map>()
            .map(_toComment)
            .toList();
      });

  @override
  Future<MyInteractions> loadMyInteractions(String issueId) async {
    final body = await _get('/api/issues/$issueId/me');
    return MyInteractions.fromJson(body);
  }

  // ── 쓰기 ────────────────────────────────────────────────────────

  @override
  Future<void> sendPost(
    String issueId, {
    String? text,
    String? imageUrl,
  }) async {
    final body = text?.trim();
    if ((body == null || body.isEmpty) && imageUrl == null) return;

    await _post('/api/issues/$issueId/posts', {
      'text': body,
      'image_url': imageUrl,
      ..._identity(issueId),
    });
  }

  @override
  Future<bool> toggleLike(String issueId, String postId) async {
    final body = await _post('/api/posts/$postId/like', const {});
    return body['liked'] == true;
  }

  @override
  Future<bool> toggleReaction(
    String issueId,
    String postId,
    String emoji,
  ) async {
    final body = await _post('/api/posts/$postId/reactions', {'emoji': emoji});
    return body['on'] == true;
  }

  @override
  Future<void> addComment(String issueId, String postId, String text) async {
    final body = text.trim();
    if (body.isEmpty) return;

    await _post('/api/posts/$postId/comments', {
      'text': body,
      ..._identity(issueId),
    });
  }

  @override
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    await _post('/api/reports', {
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
  }

  // ── 내부 ────────────────────────────────────────────────────────

  /// 닉네임은 서버가 아니라 클라이언트가 만든다.
  /// 서버가 만들려면 uid↔닉네임 연결을 저장해야 하는데, 그게 바로
  /// 이 서비스가 만들지 않기로 한 것이다. Supabase 경로와 동일한 규칙.
  Map<String, dynamic> _identity(String issueId) => {
        'nickname': AnonIdentity.nicknameFor(userId: anonId, roomId: issueId),
        'color_seed':
            AnonIdentity.colorSeedFor(userId: anonId, roomId: issueId),
      };

  List<Issue> _issueList(Object? raw) => ((raw as List?) ?? const [])
      .whereType<Map>()
      .map((e) => Issue.fromRow(Map<String, dynamic>.from(e)))
      .toList();

  Post _toPost(Map<dynamic, dynamic> row) =>
      Post.fromRow(Map<String, dynamic>.from(row), currentUserId: anonId);

  Comment _toComment(Map<dynamic, dynamic> row) =>
      Comment.fromRow(Map<String, dynamic>.from(row), currentUserId: anonId);

  /// 즉시 한 번 받고, 이후 주기적으로 갱신한다.
  ///
  /// 한 번 실패했다고 스트림을 끊지 않는다. 수집기를 재시작하는 동안
  /// 화면이 죽어버리면 개발이 불편해진다. 연속 실패만 오류로 올린다.
  Stream<T> _poll<T>(Duration interval, Future<T> Function() fetch) async* {
    var consecutiveFailures = 0;

    while (!_disposed) {
      try {
        yield await fetch();
        consecutiveFailures = 0;
      } catch (error) {
        consecutiveFailures++;
        if (consecutiveFailures >= 3) {
          throw CollectorException(
            '수집기에 연결할 수 없습니다 ($baseUrl).\n'
            'collector 디렉터리에서 실행 중인지 확인하세요.',
          );
        }
      }
      await Future<void>.delayed(interval);
    }
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _client
        .get(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 10));
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    final body = text.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(text) as Map);

    if (response.statusCode >= 400) {
      // 수집기는 도배 차단 등을 한국어 메시지로 돌려준다.
      // Supabase 경로와 같은 문구를 쓰므로 UI 는 어느 쪽이든 동일하게 보인다.
      throw CollectorException(
        body['error'] as String? ?? '요청을 처리하지 못했습니다. (${response.statusCode})',
      );
    }
    return body;
  }
}
