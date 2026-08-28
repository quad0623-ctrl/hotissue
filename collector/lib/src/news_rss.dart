import 'package:xml/xml.dart';

import 'source.dart';

/// 언론사 표준 RSS 파서.
///
/// 제목·리드·링크를 가져온다. 리드는 피드의 `<description>` 이다 —
/// 언론사가 배포 목적으로 넣은 값이고, 기사 본문을 긁어오는 것과는 다르다.
/// 피드 등장 순서를 순위로 쓴다 — 편집상 중요도의 근사값이다.
///
/// 여기서 모은 헤드라인은 이슈를 *만들지* 않는다.
/// 구글 트렌드가 뽑은 키워드가 실제로 보도되고 있는지 확인하는 용도다.
/// 그래야 "검색에서 떴다"와 "언론이 다룬다"가 분리된 신호로 남는다.
List<Headline> parseNewsRss(String xmlBody, {int limit = 60}) {
  final doc = XmlDocument.parse(xmlBody);
  final items = doc.findAllElements('item');

  final headlines = <Headline>[];
  var rank = 0;

  for (final item in items) {
    final title = _text(item, 'title');
    if (title == null || title.isEmpty) continue;

    rank++;
    headlines.add(
      Headline(
        title: title,
        rank: rank,
        summary: _clean(_text(item, 'description')),
        url: _text(item, 'link'),
        publishedAt: _text(item, 'pubDate'),
      ),
    );

    if (headlines.length >= limit) break;
  }

  return headlines;
}

/// description 에는 태그가 섞여 온다. 텍스트만 남기되 **문장은 바꾸지 않는다.**
String? _clean(String? raw) {
  if (raw == null) return null;
  // 이스케이프가 한 번 더 걸려 오는 피드가 있다 (&quot; 등).
  // Edge Function 의 stripTags 와 같은 처리를 해야 두 구현이 갈리지 않는다.
  final plain = raw
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (plain.isEmpty) return null;
  return plain.length <= 600 ? plain : plain.substring(0, 600);
}

String? _text(XmlElement parent, String localName) {
  final el =
      parent.childElements.where((e) => e.localName == localName).firstOrNull;
  final value = el?.innerText.trim();
  return (value == null || value.isEmpty) ? null : value;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
