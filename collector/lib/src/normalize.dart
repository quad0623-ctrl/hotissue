/// 키워드 매칭용 정규화.
///
/// 트렌드 키워드가 뉴스 헤드라인에 실제로 등장하는지 보려면 표기 차이를 지워야 한다.
/// `한국은행 기준금리` 와 `한국은행, 기준금리 동결` 은 같은 것을 가리킨다.
library;

final _stripPattern = RegExp(r'[^가-힣ㄱ-ㅎㅏ-ㅣa-z0-9]');
final _splitPattern = RegExp(r'\s+');

/// 공백·문장부호를 모두 제거하고 소문자로.
String normalize(String input) =>
    input.toLowerCase().replaceAll(_stripPattern, '');

/// 토큰 단위 정규화 (다어절 키워드 매칭용)
List<String> tokenize(String input) => input
    .toLowerCase()
    .split(_splitPattern)
    .map((t) => t.replaceAll(_stripPattern, ''))
    .where((t) => t.isNotEmpty)
    .toList();

/// [haystack] 이 [keyword] 를 다루고 있는가.
///
/// 두 가지로 본다.
///  1. 정규화 후 통째로 포함 — `기준금리` ⊂ `한국은행기준금리동결`
///  2. 모든 토큰이 각각 포함 — `손흥민 골` 이 `골 넣은 손흥민` 에도 걸리게
///
/// 2글자 미만 키워드는 오탐이 너무 많아 건너뛴다.
bool mentions(String haystack, String keyword) {
  final k = normalize(keyword);
  if (k.length < 2) return false;

  final h = normalize(haystack);
  if (h.contains(k)) return true;

  // 한 글자 토큰(골·법·물)도 한국어에서는 의미가 있으므로 버리지 않는다.
  // 대신 토큰이 2개 이상이고 그중 최소 하나는 두 글자 이상이어야 한다 —
  // 전부 한 글자면 아무 기사에나 걸린다.
  final tokens = tokenize(keyword);
  if (tokens.length < 2) return false;
  if (!tokens.any((t) => t.length >= 2)) return false;

  return tokens.every(h.contains);
}

/// 재시작해도 유지되는 이슈 ID. 정규화 키워드의 FNV-1a 해시.
String issueIdFor(String keyword) {
  final input = normalize(keyword);
  var hash = 0x811c9dc5;
  for (var i = 0; i < input.length; i++) {
    hash ^= input.codeUnitAt(i);
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return 'iss_${hash.toRadixString(16).padLeft(8, '0')}';
}
