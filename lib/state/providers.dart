import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// show 로 좁힌다. supabase_flutter 는 이름이 많아 Riverpod 과 충돌할 여지를 남기지 않는다.
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../core/backend/backend_bootstrap.dart';
import '../core/config/app_config.dart';
import '../data/repositories/http_issue_repository.dart';
import '../data/repositories/issue_repository.dart';
import '../data/repositories/mock_issue_repository.dart';
import '../data/repositories/supabase_issue_repository.dart';
import '../domain/models/issue.dart';
import '../domain/models/post.dart';
import '../domain/ranking/hot_score.dart';
import '../domain/ranking/ranked_issue.dart';

/// main()에서 실제 값으로 덮어쓴다. 어느 백엔드로 떴는지 + 익명 ID.
final backendSetupProvider = Provider<BackendSetup>(
  (_) => throw UnimplementedError('main()에서 override 해야 합니다'),
);

/// 백엔드 교체 지점. 이 한 곳만 보면 어느 구현이 도는지 알 수 있다.
final issueRepositoryProvider = Provider<IssueRepository>((ref) {
  final setup = ref.watch(backendSetupProvider);

  final IssueRepository repo = switch (setup.mode) {
    BackendMode.supabase => SupabaseIssueRepository(Supabase.instance.client),
    BackendMode.collector => HttpIssueRepository(
        baseUrl: AppConfig.collectorUrl,
        anonId: setup.anonId,
      ),
    BackendMode.mock => MockIssueRepository(),
  };

  ref.onDispose(repo.dispose);
  return repo;
});

final rankingServiceProvider =
    Provider<RankingService>((_) => RankingService());

final rankingModeProvider = StateProvider<RankingMode>(
  (_) => RankingMode.balanced,
);

/// 수집기에서 들어오는 원본 순위 스트림
final issuesStreamProvider = StreamProvider<List<Issue>>((ref) {
  return ref.watch(issueRepositoryProvider).watchIssues();
});

/// 자체 로직으로 정렬된 최종 순위표
final rankedIssuesProvider = Provider<AsyncValue<List<RankedIssue>>>((ref) {
  final mode = ref.watch(rankingModeProvider);
  final service = ref.watch(rankingServiceProvider);

  return ref.watch(issuesStreamProvider).whenData(
        (issues) => service.rank(issues, mode),
      );
});

/// 이슈 단건 조회.
/// 실시간 목록에 없으면 아카이브에서 찾는다 (아카이브 탭 진입 · 딥링크 대비).
final issueByIdProvider = Provider.family<RankedIssue?, String>((ref, id) {
  for (final r in ref.watch(rankedIssuesProvider).valueOrNull ?? const []) {
    if (r.issue.id == id) return r;
  }

  final archived = ref.watch(archiveProvider).valueOrNull;
  if (archived == null) return null;

  final engine =
      HotScoreEngine(weights: ref.watch(rankingModeProvider).weights);
  for (final issue in archived) {
    if (issue.id != id) continue;
    return RankedIssue(
      issue: issue,
      // 순위표에서 내려온 이슈라 현재 순위가 없다
      position: 0,
      breakdown: engine.score(issue),
      status: IssueStatus.archived,
    );
  }
  return null;
});

final postsProvider = StreamProvider.family<List<Post>, String>((ref, issueId) {
  return ref.watch(issueRepositoryProvider).watchPosts(issueId);
});

/// 글을 펼칠 때만 구독한다. 방 전체 댓글을 한꺼번에 들고 있지 않기 위해서.
final commentsProvider =
    StreamProvider.family<List<Comment>, String>((ref, postId) {
  return ref.watch(issueRepositoryProvider).watchComments(postId);
});

final archiveProvider = FutureProvider<List<Issue>>((ref) {
  return ref.watch(issueRepositoryProvider).fetchArchive();
});

/// 내가 이 방에서 누른 추천/반응.
///
/// 서버가 토글 결과를 돌려주므로 클라이언트는 그 값만 반영한다.
/// 낙관적 업데이트를 하지 않는 이유: 추천 수는 Realtime으로 어차피 즉시 갱신되고,
/// 하이라이트만 서버 응답을 기다리면 상태 불일치가 생길 여지가 없다.
final myInteractionsProvider = AsyncNotifierProvider.family<
    MyInteractionsNotifier, MyInteractions, String>(MyInteractionsNotifier.new);

class MyInteractionsNotifier
    extends FamilyAsyncNotifier<MyInteractions, String> {
  @override
  FutureOr<MyInteractions> build(String issueId) {
    return ref.watch(issueRepositoryProvider).loadMyInteractions(issueId);
  }

  MyInteractions get _current => state.valueOrNull ?? const MyInteractions();

  Future<void> toggleLike(String postId) async {
    final liked =
        await ref.read(issueRepositoryProvider).toggleLike(arg, postId);
    state = AsyncData(_current.withLike(postId, liked));
  }

  Future<void> toggleReaction(String postId, String emoji) async {
    final on = await ref
        .read(issueRepositoryProvider)
        .toggleReaction(arg, postId, emoji);
    state = AsyncData(_current.withReaction(postId, emoji, on));
  }
}
