import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models/post.dart';
import '../../state/providers.dart';
import 'widgets/catch_up_card.dart';
import 'widgets/composer.dart';
import 'widgets/post_tile.dart';

/// 이슈 하나 = 채팅방 하나.
///
/// 실시간 대화방이면서 동시에 "나중에 온 사람이 읽는 기록"이어야 하므로
/// 최상단에 [CatchUpCard]로 지금까지의 흐름을 요약해서 보여준다.
class RoomPage extends ConsumerStatefulWidget {
  const RoomPage({super.key, required this.issueId});

  final String issueId;

  @override
  ConsumerState<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends ConsumerState<RoomPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ranked = ref.watch(issueByIdProvider(widget.issueId));
    final posts = ref.watch(postsProvider(widget.issueId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ranked?.issue.keyword ?? '이슈',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (ranked != null)
              Text(
                ranked.position == 0
                    ? '아카이브 · ${relativeTime(ranked.issue.lastSeenAt)}까지 이어짐'
                    : '${ranked.position}위 · 글 ${ranked.issue.stats.posts}개',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share, size: 18),
            tooltip: '공유',
            onPressed: () => _toast(context, '공유 링크가 복사되었습니다 (Phase 4)'),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, size: 20),
            tooltip: '더보기',
            onPressed: () => _showRoomMenu(context),
          ),
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1),
          Expanded(
            child: posts.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.hot),
              ),
              error: (e, _) => Center(child: Text('불러오기 실패: $e')),
              data: (list) => _PostList(
                posts: list,
                controller: _scrollController,
                header: ranked == null
                    ? null
                    : CatchUpCard(ranked: ranked, posts: list),
              ),
            ),
          ),
          Composer(
            onSend: _send,
            onAttachImage: () => _toast(context, '이미지 업로드는 Phase 2에서 연결됩니다'),
          ),
        ],
      ),
    );
  }

  Future<void> _send(String text) async {
    try {
      await ref
          .read(issueRepositoryProvider)
          .sendPost(widget.issueId, text: text);
      _jumpToBottom();
    } catch (error) {
      // 도배 차단 트리거 등 서버가 거절한 이유를 그대로 보여준다.
      if (mounted) _toast(context, '$error');
    }
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _showRoomMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_none, size: 20),
              title: const Text('이 이슈 알림 받기', style: TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.pop(sheetContext);
                _toast(context, '푸시 알림은 Phase 4에서 연결됩니다');
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, size: 20),
              title: const Text('방 신고하기', style: TextStyle(fontSize: 14)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _reportRoom();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _reportRoom() async {
    try {
      await ref.read(issueRepositoryProvider).report(
            targetType: 'issue',
            targetId: widget.issueId,
            reason: 'user_report',
          );
      if (mounted) _toast(context, '신고가 접수되었습니다');
    } catch (error) {
      if (mounted) _toast(context, '$error');
    }
  }
}

class _PostList extends StatelessWidget {
  const _PostList({
    required this.posts,
    required this.controller,
    this.header,
  });

  final List<Post> posts;
  final ScrollController controller;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty && header == null) return const _EmptyRoom();

    final headerCount = header == null ? 0 : 1;

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: posts.length + headerCount + (posts.isEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        if (header != null && index == 0) return header!;
        if (posts.isEmpty) return const _EmptyRoom();

        return PostTile(post: posts[index - headerCount]);
      },
    );
  }
}

/// Supabase에 갓 만든 방은 비어 있다. 첫 발화를 유도하는 게 이 화면의 역할.
class _EmptyRoom extends StatelessWidget {
  const _EmptyRoom();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(32, 48, 32, 48),
      child: Column(
        children: [
          Icon(Icons.forum_outlined, size: 36, color: AppColors.textTertiary),
          SizedBox(height: 12),
          Text(
            '아직 아무도 말하지 않았습니다',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            '첫 글을 남기면 나중에 온 사람들이 그걸 먼저 보게 됩니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        duration: const Duration(seconds: 2),
      ),
    );
}
