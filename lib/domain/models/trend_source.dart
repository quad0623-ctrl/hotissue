/// 수집 소스.
///
/// **수집기가 실제로 읽는 곳만 넣는다.** 여기 있는데 수집하지 않으면
/// 설정 화면이 거짓말을 하게 되고, 확산도 계산도 왜곡된다.
///
/// 전부 공식 RSS 신디케이션 피드다. HTML 스크래핑은 하지 않는다.
/// 수집기 쪽 정의는 `collector/lib/src/source.dart` 와 id 가 일치해야 한다.
enum TrendSource {
  /// 무엇이 이슈인지 정의하는 소스
  googleTrends('구글 트렌드', 'GG', 1.00),

  /// 이슈가 실제로 보도되는지 확인하는 소스들
  yna('연합뉴스', 'YN', 0.90),
  khan('경향신문', 'KH', 0.75),
  sbs('SBS', 'SB', 0.75),
  mk('매일경제', 'MK', 0.70),
  donga('동아일보', 'DA', 0.70),
  jtbc('JTBC', 'JT', 0.70),

  /// 수집기에 새 소스가 추가됐는데 앱이 아직 모를 때의 착지점.
  /// 구버전 클라이언트가 죽지 않게 하려는 장치다.
  other('기타', '··', 0.50);

  const TrendSource(this.label, this.code, this.weight);

  /// UI 표시명
  final String label;

  /// 뱃지에 쓰는 2글자 코드
  final String code;

  /// 소스 신뢰도 가중치 (0~1)
  final double weight;

  /// 설정 화면에 보여줄 소스 (폴백 항목 제외)
  static List<TrendSource> get visible =>
      TrendSource.values.where((s) => s != TrendSource.other).toList();

  /// DB/수집기가 준 문자열을 되돌린다. 모르는 소스는 [other] 로 떨어진다.
  static TrendSource fromDb(String? name) {
    for (final s in TrendSource.values) {
      if (s.name == name) return s;
    }
    return TrendSource.other;
  }
}
