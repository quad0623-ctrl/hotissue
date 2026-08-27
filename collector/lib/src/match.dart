import 'normalize.dart';

/// 트렌드 키워드가 어떤 언론사에서 다뤄지고 있는지 판정한다.
///
/// 두 가지 방법을 쓴다. 하나만으로는 부족하다는 걸 실제 데이터로 확인했다.
///
/// **1. 키워드 직접 매칭** — 헤드라인에 키워드가 그대로 들어간 경우.
///    `대장내시경` → "대장내시경 안 해도…" 처럼 딱 맞을 때만 걸린다.
///
/// **2. 같은 기사 판정** — 구글 트렌드가 물고 온 기사 제목과
///    언론사 헤드라인의 토큰이 충분히 겹치면 같은 사건으로 본다.
///    검색어 표기와 기사 표기가 다를 때(`기후동행카드` vs `기후동행패스`)를 잡는다.
///
/// 그래도 안 걸리는 키워드가 많은데, 그건 버그가 아니다.
/// `엘지트윈스` `국선변호인` 같은 건 오늘의 기사거리가 아니라 검색 호기심이다.
/// 그 둘을 가르는 게 확산도의 목적이다.
class StoryMatcher {
  const StoryMatcher({
    this.minSharedTokens = 2,
    this.minOverlapRatio = 0.35,
  });

  /// 같은 기사로 보려면 최소 몇 개 토큰이 겹쳐야 하는가
  final int minSharedTokens;

  /// 짧은 쪽 제목 기준 겹침 비율 하한
  final double minOverlapRatio;

  /// [headline] 이 [keyword] 또는 [storyTitle] 이 가리키는 사건을 다루는가.
  bool matches(String headline, String keyword, String? storyTitle) {
    if (mentions(headline, keyword)) return true;
    if (storyTitle == null || storyTitle.isEmpty) return false;
    return sameStory(headline, storyTitle);
  }

  /// 두 제목이 같은 사건을 가리키는가 (토큰 겹침 기반)
  bool sameStory(String a, String b) {
    final ta = _contentTokens(a);
    final tb = _contentTokens(b);
    if (ta.isEmpty || tb.isEmpty) return false;

    final overlap = ta.intersection(tb).length;
    if (overlap < minSharedTokens) return false;

    final smaller = ta.length < tb.length ? ta.length : tb.length;
    return overlap / smaller >= minOverlapRatio;
  }

  Set<String> _contentTokens(String text) =>
      tokenize(text).where((t) => t.length >= 2).toSet();
}
