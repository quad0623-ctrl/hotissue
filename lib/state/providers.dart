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

// ── 데이터 신선도 ────────────────────────────────────────────────
//
// 순위 데이터는 5분에 한 번만 바뀐다. 그 사이 화면이 살아있다는 걸 보여주는
// 유일하게 정직한 값이 "마지막 갱신 이후 흐른 시간"이다. 이건 매초 바뀐다.

/// pg_cron 의 수집 주기. `supabase/migrations/..._cron_collect.sql` 과 맞춰야 한다.
const kCollectInterval = Duration(minutes: 5);

/// 이 시간을 넘겨도 갱신이 없으면 수집이 멈춘 것으로 본다.
/// 한 사이클을 통째로 놓칠 여유를 준다 — 네트워크 지연으로 오탐하면 안 된다.
const kStaleAfter = Duration(minutes: 11);

/// 1초 틱.
///
/// **시간을 표시하는 위젯만 구독할 것.** 순위 리스트가 이걸 구독하면
/// 데이터가 안 바뀌어도 매초 리빌드된다.
final tickProvider = StreamProvider<DateTime>((ref) {
  return Stream<DateTime>.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now(),
  );
});

/// 수집기가 마지막으로 쓴 시각.
///
/// 클라이언트가 응답을 받은 시각이 아니다. 그건 폴링 주기를 반영할 뿐
/// 데이터가 실제로 새것인지는 말해주지 않는다.
final lastCollectedAtProvider = Provider<DateTime?>((ref) {
  final issues = ref.watch(issuesStreamProvider).valueOrNull;
  if (issues == null || issues.isEmpty) return null;

  return issues.map((i) => i.lastSeenAt).reduce((a, b) => a.isAfter(b) ? a : b);
});

enum FreshnessState {
  /// 방금 갱신됨. 도트가 강하게 퍼진다.
  justUpdated,

  /// 정상 대기. 다음 갱신까지 카운트다운.
  waiting,

  /// 갱신이 끊겼다. 화면이 조용히 거짓말하지 않게 상태를 드러낸다.
  stale,

  /// 아직 데이터를 못 받음.
  unknown,
}

class DataFreshness {
  const DataFreshness({
    required this.state,
    required this.age,
    required this.untilNext,
  });

  final FreshnessState state;

  /// 마지막 수집 이후 흐른 시간
  final Duration age;

  /// 다음 수집까지 남은 예상 시간 (지났으면 Duration.zero)
  final Duration untilNext;

  /// `12초 전 갱신` / `2분 14초 전` / `갱신 지연 · 13분째`
  String get ageLabel {
    if (state == FreshnessState.unknown) return '연결 중';
    if (age.inSeconds < 5) return '방금 갱신';
    if (age.inMinutes < 1) return '${age.inSeconds}초 전 갱신';
    if (state == FreshnessState.stale) return '갱신 지연 · ${age.inMinutes}분째';
    return '${age.inMinutes}분 ${age.inSeconds % 60}초 전';
  }

  /// `다음 4:48`. 지연 상태이거나 알 수 없으면 null.
  String? get nextLabel {
    if (state != FreshnessState.waiting) return null;
    if (untilNext == Duration.zero) return '갱신 대기 중';

    final m = untilNext.inMinutes;
    final s = untilNext.inSeconds % 60;
    return '다음 $m:${s.toString().padLeft(2, '0')}';
  }
}

/// 매초 갱신되는 신선도. 헤더 전용이다.
final dataFreshnessProvider = Provider<DataFreshness>((ref) {
  final now = ref.watch(tickProvider).valueOrNull ?? DateTime.now();
  final at = ref.watch(lastCollectedAtProvider);

  if (at == null) {
    return const DataFreshness(
      state: FreshnessState.unknown,
      age: Duration.zero,
      untilNext: Duration.zero,
    );
  }

  final age = now.difference(at);
  final remaining = kCollectInterval - age;

  final state = age >= kStaleAfter
      ? FreshnessState.stale
      : age.inSeconds < 5
          ? FreshnessState.justUpdated
          : FreshnessState.waiting;

  return DataFreshness(
    state: state,
    age: age.isNegative ? Duration.zero : age,
    untilNext: remaining.isNegative ? Duration.zero : remaining,
  );
});
