import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'google_trends.dart';
import 'match.dart';
import 'news_rss.dart';
import 'normalize.dart';
import 'source.dart';
import 'store.dart';

/// 수집 루프.
///
/// **트렌드가 이슈를 정의하고, 뉴스는 그걸 검증한다.**
/// 뉴스 헤드라인에만 있고 검색 트렌드에 없는 키워드로는 이슈를 만들지 않는다.
/// 그러면 "인기 검색어" 서비스가 아니라 "뉴스 키워드" 서비스가 되기 때문이다.
///
/// 대신 트렌드 키워드가 몇 개 언론사에 실제로 보도되는지가 확산도 점수가 된다.
/// 한 곳을 조작하는 건 쉽지만 검색과 보도를 동시에 조작하긴 어렵다 —
/// 이게 어뷰징 방어의 실체다.
class Collector {
  Collector({
    required this.store,
    http.Client? client,
    this.archiveAfter = const Duration(hours: 6),
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final Store store;
  final http.Client _client;

  /// 이 시간 동안 다시 관측되지 않으면 아카이브로 내린다.
  final Duration archiveAfter;
  final Duration timeout;

  final _matcher = const StoryMatcher();

  DateTime? lastRunAt;
  String? lastError;
  final Map<String, String> sourceStatus = {};

  static const _userAgent =
      'hotissue-collector/0.1 (+prototype; contact: repo owner)';

  Future<void> runOnce() async {
    final now = DateTime.now();

    final trendSource = kOutlets.firstWhere((s) => s.kind == SourceKind.trends);
    final newsSources =
        kOutlets.where((s) => s.kind == SourceKind.news).toList();

    // 트렌드가 실패하면 이번 사이클은 통째로 건너뛴다.
    // 이슈를 정의하는 소스라 대체재가 없다.
    final List<TrendEntry> trends;
    try {
      trends = parseGoogleTrends(await _fetch(trendSource.feeds.first));
      sourceStatus[trendSource.id] = 'ok (${trends.length})';
    } catch (error) {
      sourceStatus[trendSource.id] = 'fail: $error';
      lastError = '트렌드 소스 실패: $error';
      stderr.writeln('[collector] $lastError');
      return;
    }

    // 언론사 하나가 죽어도, 그 언론사의 섹션 피드 하나가 죽어도 서비스는 계속된다.
    final headlines = <String, List<Headline>>{};
    for (final outlet in newsSources) {
      final collected = <Headline>[];
      var failed = 0;

      for (final feed in outlet.feeds) {
        try {
          final list = parseNewsRss(await _fetch(feed));
          // 언론사 안에서 순번을 이어 붙인다. 앞 섹션일수록 상단으로 본다.
          for (final h in list) {
            collected.add(
              Headline(
                title: h.title,
                rank: collected.length + 1,
                url: h.url,
              ),
            );
          }
        } catch (error) {
          failed++;
          stderr.writeln('[collector] ${outlet.label} 피드 실패 ($feed): $error');
        }
      }

      headlines[outlet.id] = collected;
      sourceStatus[outlet.id] = failed == 0
          ? 'ok (${collected.length})'
          : 'partial (${collected.length}, 피드 $failed개 실패)';
    }

    final seenIds = <String>{};

    for (final entry in trends) {
      final id = issueIdFor(entry.keyword);
      seenIds.add(id);

      final previous = store.issues[id];
      final previousRanks = <String, int>{
        for (final r in previous?.ranks ?? const [])
          '${r['source']}': (r['rank'] as num).toInt(),
      };

      final ranks = <Map<String, dynamic>>[
        _rank(trendSource.id, entry.rank, previousRanks, now),
      ];

      for (final outlet in newsSources) {
        final position = _bestMention(
          headlines[outlet.id] ?? const [],
          entry.keyword,
          entry.newsTitle,
        );
        if (position == null) continue;
        ranks.add(_rank(outlet.id, _newsRank(position), previousRanks, now));
      }

      final record = previous ??
          IssueRecord(
            id: id,
            keyword: entry.keyword,
            normalizedKeyword: normalize(entry.keyword),
            firstSeenAt: now,
            lastSeenAt: now,
          );

      record
        ..ranks = ranks
        ..lastSeenAt = now
        ..summary = entry.newsSnippet ?? entry.newsTitle ?? record.summary
        ..sourceTitle = entry.newsTitle ?? record.sourceTitle
        ..sourceUrl = entry.newsUrl ?? record.sourceUrl
        ..sourceOutlet = entry.newsOutlet ?? record.sourceOutlet
        ..approxTraffic = entry.approxTraffic ?? record.approxTraffic
        ..status = _status(previousRanks, ranks, isNew: previous == null);

      store.issues[id] = record;
    }

    _linkRelated(trends, headlines);
    _archiveStale(seenIds, now);
    store.recountAll();

    lastRunAt = now;
    lastError = null;
    await store.save();
  }

  Future<String> _fetch(String url) async {
    final response = await _client.get(
      Uri.parse(url),
      headers: {'User-Agent': _userAgent},
    ).timeout(timeout);

    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    // 한국 언론사 피드는 대부분 UTF-8 이지만 헤더가 없는 경우가 있어
    // http 패키지가 latin-1 로 해석해버린다. 바이트에서 직접 디코딩한다.
    return _decode(response);
  }

  /// 한국 언론사 피드는 UTF-8 이지만 Content-Type 에 charset 이 없는 경우가 있어
  /// http 패키지가 latin-1 로 해석해버린다. 바이트에서 직접 디코딩한다.
  static String _decode(http.Response response) {
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (contentType.contains('euc-kr') || contentType.contains('ks_c_5601')) {
      // EUC-KR 피드는 현재 목록에 없다. 생기면 여기에 디코더를 붙인다.
      return response.body;
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Map<String, dynamic> _rank(
    String sourceId,
    int rank,
    Map<String, int> previousRanks,
    DateTime now,
  ) =>
      {
        'source': sourceId,
        'rank': rank,
        'previous_rank': previousRanks[sourceId],
        'observed_at': now.toUtc().toIso8601String(),
      };

  /// 헤드라인 목록에서 이 사건이 등장하는 가장 앞 위치. 없으면 null.
  int? _bestMention(
    List<Headline> headlines,
    String keyword,
    String? storyTitle,
  ) {
    for (final h in headlines) {
      if (_matcher.matches(h.title, keyword, storyTitle)) return h.rank;
    }
    return null;
  }

  /// 언론사 안에서의 헤드라인 위치를 순위(1~20)로 환산한다.
  ///
  /// HotScore 의 rankHorizon 이 20이라 그 이상은 전부 0점이 된다.
  /// 그런데 300번째 헤드라인에 걸린 것도 "그 언론사가 다뤘다"는 사실 자체는 같다.
  /// 앞쪽은 촘촘하게, 뒤로 갈수록 완만하게 압축한다.
  ///   1~10   → 그대로 (헤드라인급)
  ///   11~50  → 11~15 (주요 기사)
  ///   51~200 → 16~19
  ///   201~   → 20 (언급됨)
  static int _newsRank(int position) {
    if (position <= 10) return position;
    if (position <= 50) return 10 + ((position - 10) / 10).ceil();
    if (position <= 200) return 15 + ((position - 50) / 50).ceil();
    return 20;
  }

  String _status(
    Map<String, int> previousRanks,
    List<Map<String, dynamic>> ranks, {
    required bool isNew,
  }) {
    if (isNew || previousRanks.isEmpty) return 'rising';

    var delta = 0;
    var compared = 0;
    for (final r in ranks) {
      final before = previousRanks['${r['source']}'];
      if (before == null) continue;
      delta += before - (r['rank'] as int);
      compared++;
    }
    if (compared == 0) return 'rising';
    if (delta > 1) return 'rising';
    if (delta < -1) return 'cooling';
    return 'steady';
  }

  /// 같은 헤드라인에 함께 등장하는 트렌드 키워드끼리 연결한다.
  /// 임의로 붙이는 태그가 아니라 실제 동시 등장이라 의미가 있다.
  void _linkRelated(
    List<TrendEntry> trends,
    Map<String, List<Headline>> headlines,
  ) {
    final allHeadlines = headlines.values.expand((e) => e).toList();

    for (final a in trends) {
      final related = <String>{};

      for (final b in trends) {
        if (a.keyword == b.keyword) continue;
        final together = allHeadlines.any(
          (h) => mentions(h.title, a.keyword) && mentions(h.title, b.keyword),
        );
        // 연관 판정은 직접 매칭만 쓴다. 같은 기사 판정까지 넣으면
        // 트렌드 기사 제목이 비슷하다는 이유로 무관한 키워드가 엮인다.
        if (together) related.add(b.keyword);
        if (related.length >= 3) break;
      }

      store.issues[issueIdFor(a.keyword)]?.relatedKeywords = related.toList();
    }
  }

  /// 이번 사이클에 안 보였고 충분히 오래된 이슈를 아카이브로 내린다.
  ///
  /// 시간 기반이라 점수 계산이 필요 없다. 서버가 HotScore 를 계산하지 않는 이유이기도 하다
  /// — 클라이언트가 정렬 모드별로 알아서 계산하므로 공식이 한 곳에만 있으면 된다.
  void _archiveStale(Set<String> seenIds, DateTime now) {
    for (final record in store.issues.values) {
      if (seenIds.contains(record.id)) continue;
      if (now.difference(record.lastSeenAt) >= archiveAfter) {
        record.status = 'archived';
      }
    }
  }

  void close() => _client.close();
}
