import 'package:xml/xml.dart';

import 'source.dart';

/// 언론사 표준 RSS 파서.
///
/// 헤드라인 **제목과 링크만** 가져온다. 본문·이미지는 건드리지 않는다.
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
    headlines.add(Headline(title: title, rank: rank, url: _text(item, 'link')));

    if (headlines.length >= limit) break;
  }

  return headlines;
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
