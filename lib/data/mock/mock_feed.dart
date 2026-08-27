import 'dart:math';

import '../../domain/models/issue.dart';
import '../../domain/models/post.dart';
import '../../domain/models/trend_source.dart';

/// Phase 0 프로토타입용 가짜 데이터.
/// 실제 수집기(Phase 3)가 붙으면 이 파일은 통째로 걷어낸다. → delete_plan.md 참조
class MockFeed {
  MockFeed({int seed = 20260827}) : _rnd = Random(seed);

  final Random _rnd;

  static const _keywords = <String>[
    '한국은행 기준금리',
    '월드컵 최종예선',
    '수도권 폭우 특보',
    '아이돌 그룹 컴백',
    '전기차 보조금 개편',
    '수능 난이도',
    '넷플릭스 신작 공개',
    '지하철 파업',
    '부동산 대책 발표',
    '반도체 수출 실적',
    '연예인 열애설',
    '태풍 북상',
    '프로야구 순위',
    '국정감사',
    '아이폰 신제품',
  ];

  static const _summaries = <String>[
    '오전 발표 직후 관련 검색이 급증했습니다.',
    '커뮤니티발 루머가 포털로 번지는 중입니다.',
    '공식 입장문이 나오면서 반응이 갈리고 있습니다.',
    '어제 대비 언급량이 3배 이상 늘었습니다.',
    '지역별 체감 차이가 커서 제보가 이어지고 있습니다.',
  ];

  static const _nicknames = <String>[
    '지나가던행인',
    '익명의목격자',
    '새벽세시',
    '팩트체커',
    '방금본사람',
    '조용한관찰자',
    '커피두잔',
    '출근길',
    '사이다',
    '중립기어',
  ];

  static const _chats = <String>[
    '이거 진짜임? 방금 기사 떴는데',
    '아까부터 검색어에 계속 있더라',
    '출처 좀요',
    '와 이건 좀 심각한데',
    '어제부터 조짐 있었음',
    '기사 링크 붙임',
    '다들 침착 ㅋㅋ',
    '이거 지역마다 다른 듯',
    '공식 발표 기다려보자',
    '헐 방금 속보 떴다',
    '나만 몰랐던 거임?',
    '내일 어떻게 되는 거지',
  ];

  /// 현재 순위표 생성.
  /// [idPrefix]를 나누면 실시간 목록과 아카이브의 ID가 겹치지 않는다.
  List<Issue> generateIssues({int count = 12, String idPrefix = 'issue'}) {
    final now = DateTime.now();
    final picked = [..._keywords]..shuffle(_rnd);

    return List.generate(count, (i) {
      final keyword = picked[i % picked.length];
      final ageMinutes = 5 + _rnd.nextInt(600);
      final firstSeen = now.subtract(Duration(minutes: ageMinutes));
      final lastSeen = now.subtract(Duration(minutes: _rnd.nextInt(20)));

      return Issue(
        id: '${idPrefix}_${i.toString().padLeft(2, '0')}',
        keyword: keyword,
        ranks: _generateRanks(now, baseRank: i + 1),
        firstSeenAt: firstSeen,
        lastSeenAt: lastSeen,
        summary: _summaries[_rnd.nextInt(_summaries.length)],
        stats: RoomStats(
          posts: _rnd.nextInt(180),
          comments: _rnd.nextInt(300),
          likes: _rnd.nextInt(120),
          reactions: _rnd.nextInt(400),
          liveUsers: _rnd.nextInt(60),
        ),
        relatedKeywords: (List.of(_keywords)..shuffle(_rnd)).take(3).toList(),
      );
    });
  }

  List<SourceRank> _generateRanks(DateTime now, {required int baseRank}) {
    final sources = [...TrendSource.visible]..shuffle(_rnd);
    final appearIn = 1 + _rnd.nextInt(4);

    return sources.take(appearIn).map((source) {
      final rank = (baseRank + _rnd.nextInt(6) - 2).clamp(1, 20);
      final hasPrev = _rnd.nextDouble() > 0.25;

      return SourceRank(
        source: source,
        rank: rank,
        previousRank:
            hasPrev ? (rank + _rnd.nextInt(9) - 3).clamp(1, 20) : null,
        observedAt: now.subtract(Duration(minutes: _rnd.nextInt(10))),
      );
    }).toList();
  }

  /// 이슈방 대화 생성
  List<Post> generatePosts(String issueId, {int count = 14}) {
    final now = DateTime.now();

    return List.generate(count, (i) {
      return Post(
        id: '${issueId}_post_$i',
        issueId: issueId,
        author: _author(i),
        createdAt: now.subtract(Duration(minutes: (count - i) * 3)),
        text: _chats[_rnd.nextInt(_chats.length)],
        // 3~4개 중 하나는 이미지 첨부로 흉내 (Phase 2에서 Storage 연동)
        imageUrl: _rnd.nextInt(4) == 0 ? 'mock://image/$issueId/$i' : null,
        likes: _rnd.nextInt(40),
        reactions: _randomReactions(),
        commentCount: _rnd.nextInt(4),
        isPinned: i == 0,
      );
    });
  }

  /// 글 하나에 달린 댓글 생성
  List<Comment> generateComments(String postId, int count) {
    final now = DateTime.now();

    return List.generate(count, (c) {
      return Comment(
        id: '${postId}_c$c',
        postId: postId,
        author: _author(postId.hashCode.abs() + c),
        text: _chats[_rnd.nextInt(_chats.length)],
        createdAt: now.subtract(Duration(minutes: (count - c) * 2)),
        likes: _rnd.nextInt(8),
      );
    });
  }

  Author _author(int i) {
    final name = _nicknames[i % _nicknames.length];
    return Author(
      id: 'anon_$i',
      nickname: name,
      colorSeed: name.hashCode,
      isMe: false,
    );
  }

  Map<String, int> _randomReactions() {
    final result = <String, int>{};
    for (final emoji in kReactionEmojis) {
      if (_rnd.nextDouble() > 0.5) {
        result[emoji] = 1 + _rnd.nextInt(30);
      }
    }
    return result;
  }

  /// 로그인한 나
  static const me = Author(
    id: 'me',
    nickname: '나',
    colorSeed: 77,
    isMe: true,
  );
}
