import 'package:flutter_test/flutter_test.dart';
import 'package:hotissue/core/identity/anon_identity.dart';

/// 익명 설계의 두 가지 약속을 테스트로 못박는다.
///  1. 같은 방에서는 같은 이름  (대화 맥락 유지)
///  2. 다른 방에서는 다른 이름  (방을 넘나드는 추적 불가)
void main() {
  const userA = 'e3b0c442-98fc-1c14-9afb-f4c8996fb924';
  const userB = '5d41402a-bc4b-2a76-b971-9d911017c592';

  group('AnonIdentity', () {
    test('같은 사용자·같은 방이면 항상 같은 닉네임', () {
      final first = AnonIdentity.nicknameFor(userId: userA, roomId: 'issue_1');
      final second = AnonIdentity.nicknameFor(userId: userA, roomId: 'issue_1');

      expect(first, second);
    });

    test('같은 사용자라도 방이 다르면 닉네임이 달라진다', () {
      final inRoom1 =
          AnonIdentity.nicknameFor(userId: userA, roomId: 'issue_1');
      final inRoom2 =
          AnonIdentity.nicknameFor(userId: userA, roomId: 'issue_2');

      expect(inRoom1, isNot(inRoom2));
    });

    test('같은 방이라도 사용자가 다르면 닉네임이 달라진다', () {
      final a = AnonIdentity.nicknameFor(userId: userA, roomId: 'issue_1');
      final b = AnonIdentity.nicknameFor(userId: userB, roomId: 'issue_1');

      expect(a, isNot(b));
    });

    test('닉네임 길이가 DB 제약(1~24자)을 넘지 않는다', () {
      // posts.nickname 에 char_length(nickname) between 1 and 24 제약이 걸려 있다.
      for (var i = 0; i < 200; i++) {
        final name =
            AnonIdentity.nicknameFor(userId: userA, roomId: 'issue_$i');
        expect(name.length, inInclusiveRange(1, 24), reason: name);
      }
    });

    test('색 시드는 항상 음수가 아니다', () {
      // 팔레트 인덱싱에 쓰므로 음수가 나오면 런타임에 터진다.
      for (var i = 0; i < 200; i++) {
        final seed =
            AnonIdentity.colorSeedFor(userId: userB, roomId: 'issue_$i');
        expect(seed, greaterThanOrEqualTo(0));
      }
    });

    test('닉네임 충돌이 심하지 않다 (같은 방 200명 기준)', () {
      // 형용사 22 × 명사 18 × 숫자 100 이므로 이론상 39,600 조합.
      // 200명이면 생일 문제로 몇 건은 겹칠 수 있으나 절반이 겹치면 설계가 잘못된 것이다.
      final names = <String>{};
      for (var i = 0; i < 200; i++) {
        names.add(AnonIdentity.nicknameFor(userId: 'user_$i', roomId: 'room'));
      }

      expect(names.length, greaterThan(180));
    });
  });
}
