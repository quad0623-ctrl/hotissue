/// 익명 신원 생성기.
///
/// **이 서비스에는 계정이 없다.** Supabase 익명 인증으로 받은 uid 하나가 전부이고,
/// 프로필도 표시 이름도 저장하지 않는다. 그런데 대화가 성립하려면 최소한
/// "아까 그 사람"을 알아볼 수는 있어야 한다.
///
/// 그래서 닉네임을 `(uid + 방id)` 해시로 만든다.
///  - 같은 방 안: 항상 같은 이름 → 대화 맥락이 유지된다
///  - 다른 방: 완전히 다른 이름 → 방을 넘나드는 추적이 불가능하다
///
/// 서버는 이 값을 검증하지 않는다. 검증하려면 uid와 닉네임의 연결을 저장해야 하는데
/// 그게 바로 우리가 만들지 않기로 한 것이기 때문이다.
abstract final class AnonIdentity {
  static const _adjectives = <String>[
    '지나가던',
    '조용한',
    '성급한',
    '느긋한',
    '진지한',
    '심드렁한',
    '출근길',
    '퇴근길',
    '새벽',
    '한밤중',
    '점심시간',
    '주말',
    '중립기어',
    '팩트체크',
    '방금온',
    '눈팅하던',
    '침착한',
    '흥분한',
    '커피마시는',
    '라면먹는',
    '이불속',
    '옥상에서',
  ];

  static const _nouns = <String>[
    '행인',
    '목격자',
    '구경꾼',
    '관찰자',
    '이웃',
    '시민',
    '직장인',
    '학생',
    '고양이',
    '너구리',
    '두더지',
    '참새',
    '독자',
    '청취자',
    '방문객',
    '통행인',
    '주민',
    '승객',
  ];

  /// 방마다 달라지는 익명 닉네임. 예: `새벽 너구리 42`
  static String nicknameFor({required String userId, required String roomId}) {
    final h = _hash('$userId::$roomId');
    final adjective = _adjectives[h % _adjectives.length];
    final noun = _nouns[(h ~/ _adjectives.length) % _nouns.length];
    final suffix = h % 100;
    return '$adjective $noun $suffix';
  }

  /// 아바타 색 시드. 닉네임과 같은 해시에서 뽑아 색과 이름이 함께 움직이게 한다.
  static int colorSeedFor({required String userId, required String roomId}) =>
      _hash('$userId::$roomId::color');

  /// FNV-1a 32비트. 암호학적 용도가 아니라 표시용이므로 이걸로 충분하고,
  /// 웹(JS 53비트 정수)에서도 오버플로 없이 동작한다.
  static int _hash(String input) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
