import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/post.dart';
import '../../../state/providers.dart';

/// 방 안의 글 한 건. 채팅 말풍선보다 게시물에 가깝게 그린다.
/// (반응/댓글/추천이 붙고, 나중에 다시 읽히는 게 목적이라)
class PostTile extends ConsumerStatefulWidget {
  const PostTile({super.key, required this.post});

  final Post post;

  @override
  ConsumerState<PostTile> createState() => _PostTileState();
}

class _PostTileState extends ConsumerState<PostTile> {
  bool _showComments = false;
  bool _showEmojiPicker = false;
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Post get _post => widget.post;
  String get _issueId => _post.issueId;

  @override
  Widget build(BuildContext context) {
    if (_post.isHidden) return const _HiddenNotice();

    final mine = ref.watch(myInteractionsProvider(_issueId)).valueOrNull ??
        const MyInteractions();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: _post.isPinned ? AppColors.surfaceHigh : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _post.isPinned ? AppColors.warm12 : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(post: _post),
          if (_post.text != null) ...[
            const SizedBox(height: 6),
            Text(
              _post.text!,
              style: const TextStyle(fontSize: 14, height: 1.45),
            ),
          ],
          if (_post.imageUrl != null) ...[
            const SizedBox(height: 8),
            _PostImage(url: _post.imageUrl!),
          ],
          const SizedBox(height: 8),
          _ReactionRow(
            reactions: _post.reactions,
            mine: mine,
            postId: _post.id,
            expanded: _showEmojiPicker,
            onReact: _react,
            onTogglePicker: () =>
                setState(() => _showEmojiPicker = !_showEmojiPicker),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _ActionButton(
                icon: mine.likes(_post.id)
                    ? Icons.favorite
                    : Icons.favorite_border,
                label: '추천 ${_post.likes}',
                color: mine.likes(_post.id) ? AppColors.hot : null,
                onTap: _like,
              ),
              const SizedBox(width: 4),
              _ActionButton(
                icon: Icons.mode_comment_outlined,
                label: '댓글 ${_post.commentCount}',
                onTap: () => setState(() => _showComments = !_showComments),
              ),
              const Spacer(),
              _ActionButton(
                icon: Icons.flag_outlined,
                label: '',
                onTap: _report,
              ),
            ],
          ),
          if (_showComments)
            _CommentSection(
              postId: _post.id,
              controller: _commentController,
              onSubmit: _comment,
            ),
        ],
      ),
    );
  }

  Future<void> _like() => _run(
        () => ref
            .read(myInteractionsProvider(_issueId).notifier)
            .toggleLike(_post.id),
      );

  Future<void> _react(String emoji) => _run(
        () => ref
            .read(myInteractionsProvider(_issueId).notifier)
            .toggleReaction(_post.id, emoji),
      );

  Future<void> _comment(String text) async {
    if (text.trim().isEmpty) return;
    _commentController.clear();
    await _run(
      () => ref
          .read(issueRepositoryProvider)
          .addComment(_issueId, _post.id, text),
    );
  }

  Future<void> _report() async {
    await _run(
      () => ref.read(issueRepositoryProvider).report(
            targetType: 'post',
            targetId: _post.id,
            reason: 'user_report',
          ),
    );
    if (mounted) _toast('신고가 접수되었습니다');
  }

  /// 서버 오류(도배 차단 등)를 사용자에게 그대로 보여준다.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) _toast('$error');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 13)),
          duration: const Duration(seconds: 2),
        ),
      );
  }
}

/// 익명 아바타 색. 닉네임 시드로 고정 팔레트에서 뽑아
/// 같은 방 안에서는 같은 사람이 같은 색으로 보이게 한다.
const _avatarPalette = <Color>[
  Color(0xFFE05252),
  Color(0xFFE08A2E),
  Color(0xFF3FA97A),
  Color(0xFF3D7FE0),
  Color(0xFF8A5CE0),
  Color(0xFFD14E8C),
  Color(0xFF4FA3B8),
  Color(0xFF9A8A3F),
];

class _Header extends StatelessWidget {
  const _Header({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final color =
        _avatarPalette[post.author.colorSeed.abs() % _avatarPalette.length];

    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            post.author.nickname.isEmpty
                ? '?'
                : post.author.nickname.substring(0, 1),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            post.author.nickname,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: post.author.isMe ? AppColors.hot : AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          relativeTime(post.createdAt),
          style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
        ),
        const Spacer(),
        if (post.isPinned)
          const Row(
            children: [
              Icon(Icons.push_pin, size: 10, color: AppColors.warm),
              SizedBox(width: 3),
              Text(
                '고정',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: AppColors.warm,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({
    required this.reactions,
    required this.mine,
    required this.postId,
    required this.onReact,
    required this.expanded,
    required this.onTogglePicker,
  });

  final Map<String, int> reactions;
  final MyInteractions mine;
  final String postId;
  final ValueChanged<String> onReact;
  final bool expanded;
  final VoidCallback onTogglePicker;

  @override
  Widget build(BuildContext context) {
    final visible = expanded ? kReactionEmojis : reactions.keys.toList();

    return Wrap(
      spacing: 5,
      runSpacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final emoji in visible)
          _ReactionChip(
            emoji: emoji,
            count: reactions[emoji],
            active: mine.reacted(postId, emoji),
            onTap: () => onReact(emoji),
          ),
        GestureDetector(
          onTap: onTogglePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(
              expanded ? Icons.close : Icons.add_reaction_outlined,
              size: 13,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String emoji;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active ? AppColors.hot12 : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? AppColors.hot : AppColors.border),
        ),
        child: Text(
          count == null ? emoji : '$emoji $count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w800 : FontWeight.w400,
            color: active ? AppColors.hot : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// 댓글은 펼칠 때 비로소 구독한다.
class _CommentSection extends ConsumerWidget {
  const _CommentSection({
    required this.postId,
    required this.controller,
    required this.onSubmit,
  });

  final String postId;
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(commentsProvider(postId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        const Divider(height: 1),
        const SizedBox(height: 6),
        comments.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '댓글 불러오는 중…',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
          ),
          error: (_, __) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '댓글을 불러오지 못했습니다',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
          ),
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final c in list) _CommentRow(comment: c)],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(fontSize: 12),
                textInputAction: TextInputAction.send,
                maxLength: 300,
                buildCounter: _noCounter,
                onSubmitted: onSubmit,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '댓글 달기',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
            GestureDetector(
              onTap: () => onSubmit(controller.text),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.send, size: 14, color: AppColors.hot),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Widget? _noCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) =>
    null;

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});

  final Comment comment;

  @override
  Widget build(BuildContext context) {
    if (comment.isHidden) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Text(
          '신고 누적으로 가려진 댓글입니다.',
          style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            comment.author.nickname,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color:
                  comment.author.isMe ? AppColors.hot : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              comment.text,
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
          Text(
            relativeTime(comment.createdAt),
            style: const TextStyle(fontSize: 9, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textTertiary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 13, color: c),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 목 백엔드의 `mock://` URL은 실제 이미지가 아니므로 자리표시자를 그린다.
/// Supabase 연결 시에는 Storage 공개 URL이 들어온다.
class _PostImage extends StatelessWidget {
  const _PostImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (!url.startsWith('http')) return const _ImagePlaceholder();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _ImagePlaceholder(),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const _ImagePlaceholder(),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, color: AppColors.textTertiary, size: 22),
          SizedBox(height: 4),
          Text(
            '첨부 이미지',
            style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _HiddenNotice extends StatelessWidget {
  const _HiddenNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        '신고 누적으로 가려진 글입니다.',
        style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
      ),
    );
  }
}
