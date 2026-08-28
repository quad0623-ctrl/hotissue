/// 수집 소스 정의.
///
/// **전부 공식 RSS 신디케이션 피드다.** HTML 스크래핑을 하지 않는다.
///  - 구글 트렌드 `/trending/rss` 는 robots.txt 가 막지 않는 공개 피드다
///    (막힌 건 `/trends/explore?` 뿐)
///  - 언론사 RSS 는 애초에 배포 목적으로 제공되는 채널이다
///
/// 저장하는 것은 **키워드·제목·링크**뿐이다. 기사 본문과 이미지는 복제하지 않고
/// 원문 링크만 건다. 판단 근거는 plan.md §6.2.
library;

/// 언론사 하나. 섹션 피드를 여러 개 가질 수 있다.
///
/// 피드가 아니라 **언론사** 단위로 묶는 게 중요하다.
/// 연합뉴스 섹션 10개를 각각 소스로 세면 확산도가 부풀려진다 —
/// "10곳에 났다"가 아니라 "한 곳의 10개 지면에 났다"이기 때문이다.
class OutletDef {
  const OutletDef({
    required this.id,
    required this.label,
    required this.code,
    required this.weight,
    required this.feeds,
    required this.kind,
  });

  /// 앱의 TrendSource enum 이름과 일치해야 한다
  final String id;
  final String label;

  /// 뱃지에 쓰는 2글자 코드
  final String code;

  /// 소스 신뢰도 가중치 (0~1)
  final double weight;

  final List<String> feeds;
  final SourceKind kind;
}

enum SourceKind {
  /// 무엇이 이슈인지 정의하는 소스. 여기 없으면 이슈가 아니다.
  trends,

  /// 이슈가 실제로 보도되는지 확인하는 소스. 확산도 점수를 만든다.
  news,
}

const _ynaSections = [
  'politics',
  'economy',
  'society',
  'international',
  'culture',
  'sports',
  'entertainment',
  'health',
  'industry',
  'local',
];

/// 활성 소스.
///
/// 뉴스 코퍼스를 넓게 잡는 이유: 좁게 잡으면 확산도가 죽는다.
/// 헤드라인 186건일 때는 트렌드 10건 중 1건만 걸렸지만,
/// 1,500건으로 늘리니 4건이 걸렸다. 나머지 6건은 실제로 오늘의 기사거리가 아닌
/// 검색 호기심이었다 — 그 둘을 가르는 게 확산도의 목적이다.
final kOutlets = <OutletDef>[
  const OutletDef(
    id: 'googleTrends',
    label: '구글 트렌드',
    code: 'GG',
    weight: 1.00,
    feeds: ['https://trends.google.com/trending/rss?geo=KR'],
    kind: SourceKind.trends,
  ),
  OutletDef(
    id: 'yna',
    label: '연합뉴스',
    code: 'YN',
    weight: 0.90,
    feeds: [
      for (final s in _ynaSections) 'https://www.yna.co.kr/rss/$s.xml',
    ],
    kind: SourceKind.news,
  ),
  const OutletDef(
    id: 'khan',
    label: '경향신문',
    code: 'KH',
    weight: 0.75,
    feeds: [
      'https://www.khan.co.kr/rss/rssdata/total_news.xml',
      'https://www.khan.co.kr/rss/rssdata/kh_sports.xml',
    ],
    kind: SourceKind.news,
  ),
  const OutletDef(
    id: 'mk',
    label: '매일경제',
    code: 'MK',
    weight: 0.70,
    feeds: [
      'https://www.mk.co.kr/rss/30000001/',
      'https://www.mk.co.kr/rss/71000001/',
      'https://www.mk.co.kr/rss/30000023/',
    ],
    kind: SourceKind.news,
  ),
  const OutletDef(
    id: 'donga',
    label: '동아일보',
    code: 'DA',
    weight: 0.70,
    feeds: ['https://rss.donga.com/total.xml'],
    kind: SourceKind.news,
  ),
  const OutletDef(
    id: 'sbs',
    label: 'SBS',
    code: 'SB',
    weight: 0.75,
    feeds: ['https://news.sbs.co.kr/news/headlineRssFeed.do?plink=RSSREADER'],
    kind: SourceKind.news,
  ),
  const OutletDef(
    id: 'jtbc',
    label: 'JTBC',
    code: 'JT',
    weight: 0.70,
    feeds: ['https://fs.jtbc.co.kr/RSS/newsflash.xml'],
    kind: SourceKind.news,
  ),
];

/// 트렌드 소스가 뽑아온 키워드 한 건.
class TrendEntry {
  const TrendEntry({
    required this.keyword,
    required this.rank,
    this.approxTraffic,
    this.imageUrl,
    this.newsTitle,
    this.newsUrl,
    this.newsOutlet,
    this.newsItems = const [],
  });

  final String keyword;

  /// 1부터. 피드 등장 순서.
  final int rank;

  /// 구글 트렌드가 주는 대략적 검색량 (예: `2000+`)
  final String? approxTraffic;

  /// 기사 썸네일 URL. 이미지를 복제하지 않고 링크만 보관한다.
  final String? imageUrl;

  final String? newsTitle;
  final String? newsUrl;
  final String? newsOutlet;

  /// 전체 news_item. 언론사 매칭이 안 된 이슈에서도 링크는 남게 한다.
  final List<TrendNewsItem> newsItems;
}

/// 뉴스 소스가 뽑아온 기사 한 건.
///
/// `summary` 는 피드의 `<description>` 이다. **언론사가 배포 목적으로 넣은 값**이고
/// 표준 RSS 리더가 그대로 보여주는 값이다. 기사 본문을 긁어오지 않는다.
class Headline {
  const Headline({
    required this.title,
    required this.rank,
    this.summary,
    this.url,
    this.publishedAt,
  });

  final String title;

  /// 1부터. 언론사 안에서의 등장 순서 = 편집상 중요도의 근사값.
  final int rank;

  /// 기사 리드. 자르되 문장을 바꾸지 않는다.
  final String? summary;

  final String? url;
  final String? publishedAt;
}

/// 구글 트렌드가 키워드마다 물고 오는 기사 (항목당 3건).
///
/// `ht:news_item_snippet` 은 담지 않는다 — 확인해 보니 늘 비어 있다(30건 전부 0자).
/// 그걸 요약으로 쓰려다 계속 제목으로 폴백해서 "헤드라인만 보인다"는 문제가 났다.
class TrendNewsItem {
  const TrendNewsItem({required this.title, this.outlet, this.url});

  final String title;
  final String? outlet;
  final String? url;
}
