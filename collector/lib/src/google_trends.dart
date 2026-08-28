import 'package:xml/xml.dart';

import 'source.dart';

/// 구글 트렌드 실시간 RSS 파서.
///
/// 이 피드는 키워드만 주지 않는다. 항목마다 대략적 검색량과 관련 기사 3건
/// (제목·언론사·URL·요약)이 함께 온다. 덕분에
///  - 요약문을 우리가 지어낼 필요가 없고 (LLM 요약은 나중 문제)
///  - 원문 링크를 걸 수 있어 저작권 측면에서도 안전한 형태가 된다
///
/// ```xml
/// <item>
///   <title>키워드</title>
///   <ht:approx_traffic>2000+</ht:approx_traffic>
///   <pubDate>...</pubDate>
///   <ht:picture>...</ht:picture>
///   <ht:news_item>
///     <ht:news_item_title>...</ht:news_item_title>
///     <ht:news_item_url>...</ht:news_item_url>
///     <ht:news_item_source>...</ht:news_item_source>
///     <ht:news_item_snippet>...</ht:news_item_snippet>
///   </ht:news_item>
/// </item>
/// ```
List<TrendEntry> parseGoogleTrends(String xmlBody) {
  final doc = XmlDocument.parse(xmlBody);
  final items = doc.findAllElements('item');

  final entries = <TrendEntry>[];
  var rank = 0;

  for (final item in items) {
    final keyword = _text(item, 'title');
    if (keyword == null || keyword.isEmpty) continue;

    rank++;

    // 첫 번째 뉴스 항목을 대표로 쓴다. 피드가 중요도 순으로 준다.
    final news =
        item.childElements.where((e) => e.localName == 'news_item').firstOrNull;

    entries.add(
      TrendEntry(
        keyword: keyword,
        rank: rank,
        approxTraffic: _text(item, 'approx_traffic'),
        imageUrl: _text(item, 'picture'),
        newsTitle: news == null ? null : _text(news, 'news_item_title'),
        newsUrl: news == null ? null : _text(news, 'news_item_url'),
        newsOutlet: news == null ? null : _text(news, 'news_item_source'),
        newsSnippet: news == null ? null : _text(news, 'news_item_snippet'),
      ),
    );
  }

  return entries;
}

/// 네임스페이스 접두사(`ht:`)가 바뀌어도 견디도록 localName 으로 찾는다.
String? _text(XmlElement parent, String localName) {
  final el =
      parent.childElements.where((e) => e.localName == localName).firstOrNull;
  final value = el?.innerText.trim();
  return (value == null || value.isEmpty) ? null : _unescape(value);
}

/// RSS 안에 이스케이프된 채 들어오는 경우가 있다.
String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
