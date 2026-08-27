import '../../domain/models/issue.dart';
import '../../domain/models/post.dart';

/// 데이터 접근 경계.
///
/// 구현은 두 가지다.
///  - [MockIssueRepository]     : 백엔드 없이 화면을 보기 위한 인메모리 목
///  - [SupabaseIssueRepository] : 실제 Postgres + Realtime
///
/// UI와 도메인은 이 인터페이스만 알기 때문에, 교체는 Provider 한 줄이다.
abstract class IssueRepository {
  /// 실시간 순위표 원본. 정렬은 HotScoreEngine이 담당한다.
  Stream<List<Issue>> watchIssues();

  /// 아카이브된 지난 이슈
  Future<List<Issue>> fetchArchive();

  /// 특정 이슈방의 글 목록
  Stream<List<Post>> watchPosts(String issueId);

  /// 특정 글의 댓글. 펼칠 때만 구독한다.
  Stream<List<Comment>> watchComments(String postId);

  /// 내가 이 방에서 누른 추천/반응. 방 진입 시 한 번 불러 하이라이트를 복원한다.
  Future<MyInteractions> loadMyInteractions(String issueId);

  Future<void> sendPost(String issueId, {String? text, String? imageUrl});

  /// 반환값 = 토글 후 상태(true = 추천함)
  Future<bool> toggleLike(String issueId, String postId);

  /// 반환값 = 토글 후 상태(true = 반응 남김)
  Future<bool> toggleReaction(String issueId, String postId, String emoji);

  Future<void> addComment(String issueId, String postId, String text);

  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
  });

  void dispose();
}
