import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'store.dart';

/// 수집한 이슈를 Supabase 로 밀어넣는다.
///
/// **왜 필요한가**: 배포본(Vercel)은 Supabase 만 본다. 수집기가 자체 저장소에만
/// 쓰면 배포된 앱에는 아무 이슈도 안 뜬다. 이 싱크가 그 다리다.
///
/// **왜 service_role 키인가**: `issues` 테이블에는 INSERT/UPDATE 정책이 없다.
/// 클라이언트가 순위를 조작하지 못하게 일부러 그렇게 뒀다. 수집기는 그 정책을
/// 넘어야 하므로 RLS 를 우회하는 키가 필요하다.
///
/// **이 키는 절대 앱 번들이나 저장소에 들어가면 안 된다.** 수집기 프로세스의
/// 환경변수로만 준다. 유출되면 누구나 이슈를 조작하고 남의 글을 지울 수 있다.
class SupabaseSink {
  SupabaseSink({
    required this.url,
    required this.serviceRoleKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// 예: `https://<ref>.supabase.co`
  final String url;
  final String serviceRoleKey;
  final http.Client _client;

  /// 환경변수가 둘 다 있을 때만 싱크를 만든다. 없으면 null — 로컬 전용 모드다.
  ///
  /// [env] 를 주면 그걸 쓴다 (`.env` 병합본). 안 주면 프로세스 환경변수.
  static SupabaseSink? fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    final url = e['SUPABASE_URL'];
    final key = e['SUPABASE_SERVICE_ROLE_KEY'];

    if (url == null || url.isEmpty || key == null || key.isEmpty) return null;
    return SupabaseSink(url: url, serviceRoleKey: key);
  }

  Map<String, String> get _headers => {
        'apikey': serviceRoleKey,
        'Authorization': 'Bearer $serviceRoleKey',
        'Content-Type': 'application/json',
        // normalized_keyword 유니크 제약에 맞춰 upsert 한다.
        // 같은 이슈가 다음 사이클에 또 오면 새 행을 만들지 않고 갱신한다.
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      };

  /// 활성 이슈를 통째로 upsert 한다.
  ///
  /// `first_seen_at` 은 보내지 않는다. 이미 있는 이슈의 최초 관측 시각을
  /// 덮어쓰면 신선도·나이 계산이 망가진다. 새 행일 때는 DB 기본값(now)이 들어간다.
  Future<SinkResult> push(Iterable<IssueRecord> issues) async {
    final rows = [
      for (final i in issues)
        {
          'keyword': i.keyword,
          'normalized_keyword': i.normalizedKeyword,
          'summary': i.summary,
          'status': i.status,
          'ranks': i.ranks,
          'related_keywords': i.relatedKeywords,
          'source_title': i.sourceTitle,
          'source_url': i.sourceUrl,
          'source_outlet': i.sourceOutlet,
          'approx_traffic': i.approxTraffic,
          'last_seen_at': i.lastSeenAt.toUtc().toIso8601String(),
        },
    ];

    if (rows.isEmpty) return const SinkResult(pushed: 0);

    final response = await _client
        .post(
          Uri.parse('$url/rest/v1/issues?on_conflict=normalized_keyword'),
          headers: _headers,
          body: jsonEncode(rows),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode >= 400) {
      return SinkResult(
        pushed: 0,
        error: 'HTTP ${response.statusCode} '
            '${utf8.decode(response.bodyBytes, allowMalformed: true).trim()}',
      );
    }
    return SinkResult(pushed: rows.length);
  }

  /// 이번 사이클에 안 보인 이슈를 아카이브로 내린다.
  ///
  /// 수집기 자체 저장소와 같은 규칙이지만, Supabase 에는 다른 기기에서 만든
  /// 이슈가 있을 수 있으므로 서버 시각 기준으로 한 번 더 정리한다.
  Future<void> archiveStale(Duration after) async {
    final cutoff = DateTime.now().toUtc().subtract(after).toIso8601String();

    await _client
        .patch(
          Uri.parse(
            '$url/rest/v1/issues'
            '?status=neq.archived&last_seen_at=lt.$cutoff',
          ),
          headers: _headers,
          body: jsonEncode({'status': 'archived'}),
        )
        .timeout(const Duration(seconds: 30));
  }

  void close() => _client.close();
}

class SinkResult {
  const SinkResult({required this.pushed, this.error});

  final int pushed;
  final String? error;

  bool get ok => error == null;
}
