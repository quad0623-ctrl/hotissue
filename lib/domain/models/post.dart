import 'json_utils.dart';

/// 이슈방에 올라오는 글/이미지 한 건.
///
/// 인스턴트 채팅방이지만 "나중에 온 사람이 읽는 기록"이 목적이므로
/// 메시지 하나하나가 반응/댓글/추천을 가지는 게시물에 가깝다.
///
/// 댓글은 여기 담지 않고 [commentCount]만 들고 다닌다.
/// 방에 글이 200개면 댓글까지 한꺼번에 스트리밍할 수 없기 때문에,
/// 실제 댓글은 펼칠 때 별도 스트림으로 가져온다.
class Post {
  const Post({
    required this.id,
    required this.issueId,
    required this.author,
    required this.createdAt,
    this.text,
    this.imageUrl,
    this.likes = 0,
    this.reactions = const {},
    this.commentCount = 0,
    this.isPinned = false,
    this.isHidden = false,
  });

  final String id;
  final String issueId;
  final Author author;
  final DateTime createdAt;

  final String? text;
  final String? imageUrl;

  /// 추천 수
  final int likes;

  /// 이모지 -> 누른 사람 수
  final Map<String, int> reactions;

  final int commentCount;

  /// 방장/자동 로직이 상단 고정한 글 (= 나중에 온 사람이 먼저 봐야 할 글)
  final bool isPinned;

  /// 신고 누적으로 가려진 글
  final bool isHidden;

  int get reactionCount => reactions.values.fold(0, (a, b) => a + b);

  /// 나중에 온 사람에게 보여줄 "하이라이트" 판정 점수.
  double get highlightScore =>
      likes * 3.0 + reactionCount * 1.0 + commentCount * 2.0;

  factory Post.fromRow(Map<String, dynamic> row, {String? currentUserId}) {
    final rawReactions = row['reaction_counts'];
    final reactions = <String, int>{};
    if (rawReactions is Map) {
      rawReactions.forEach((key, value) {
        final count = (value as num?)?.toInt() ?? 0;
        if (count > 0) reactions['$key'] = count;
      });
    }

    final authorId = row['author_id'] as String? ?? 'anon';

    return Post(
      id: row['id'] as String,
      issueId: row['issue_id'] as String,
      author: Author(
        id: authorId,
        nickname: row['nickname'] as String? ?? '익명',
        colorSeed: (row['color_seed'] as num?)?.toInt() ?? 0,
        isMe: currentUserId != null && currentUserId == authorId,
      ),
      createdAt: parseTime(row['created_at']),
      text: row['body'] as String?,
      imageUrl: row['image_url'] as String? ?? row['image_path'] as String?,
      likes: (row['likes_count'] as num?)?.toInt() ?? 0,
      reactions: reactions,
      commentCount: (row['comments_count'] as num?)?.toInt() ?? 0,
      isPinned: row['is_pinned'] as bool? ?? false,
      isHidden: row['is_hidden'] as bool? ?? false,
    );
  }

  Post copyWith({
    int? likes,
    Map<String, int>? reactions,
    int? commentCount,
    bool? isPinned,
    bool? isHidden,
  }) {
    return Post(
      id: id,
      issueId: issueId,
      author: author,
      createdAt: createdAt,
      text: text,
      imageUrl: imageUrl,
      likes: likes ?? this.likes,
      reactions: reactions ?? this.reactions,
      commentCount: commentCount ?? this.commentCount,
      isPinned: isPinned ?? this.isPinned,
      isHidden: isHidden ?? this.isHidden,
    );
  }
}

class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.author,
    required this.text,
    required this.createdAt,
    this.likes = 0,
    this.isHidden = false,
  });

  final String id;
  final String postId;
  final Author author;
  final String text;
  final DateTime createdAt;
  final int likes;
  final bool isHidden;

  factory Comment.fromRow(Map<String, dynamic> row, {String? currentUserId}) {
    final authorId = row['author_id'] as String? ?? 'anon';

    return Comment(
      id: row['id'] as String,
      postId: row['post_id'] as String,
      author: Author(
        id: authorId,
        nickname: row['nickname'] as String? ?? '익명',
        colorSeed: (row['color_seed'] as num?)?.toInt() ?? 0,
        isMe: currentUserId != null && currentUserId == authorId,
      ),
      text: row['body'] as String? ?? '',
      createdAt: parseTime(row['created_at']),
      likes: (row['likes_count'] as num?)?.toInt() ?? 0,
      isHidden: row['is_hidden'] as bool? ?? false,
    );
  }
}

/// 익명 사용자. 계정이 없으므로 프로필도 없다.
/// [nickname]과 [colorSeed]는 서버가 아니라 작성자 클라이언트가
/// `(uid + 방id)` 해시로 만들어 글에 박아 넣은 값이다. → AnonIdentity 참조
class Author {
  const Author({
    required this.id,
    required this.nickname,
    required this.colorSeed,
    this.isMe = false,
  });

  final String id;
  final String nickname;

  /// 아바타 색 생성용 시드
  final int colorSeed;

  final bool isMe;
}

/// 내가 이 방에서 누른 추천/반응. 하이라이트 표시와 토글 판단에 쓴다.
class MyInteractions {
  const MyInteractions({
    this.likedPostIds = const {},
    this.reactionsByPost = const {},
  });

  final Set<String> likedPostIds;
  final Map<String, Set<String>> reactionsByPost;

  bool likes(String postId) => likedPostIds.contains(postId);

  bool reacted(String postId, String emoji) =>
      reactionsByPost[postId]?.contains(emoji) ?? false;

  factory MyInteractions.fromJson(Map<String, dynamic> json) {
    final rawLikes = json['likes'];
    final rawReactions = json['reactions'];

    final reactions = <String, Set<String>>{};
    if (rawReactions is Map) {
      rawReactions.forEach((postId, emojis) {
        if (emojis is List) {
          reactions['$postId'] = emojis.map((e) => '$e').toSet();
        }
      });
    }

    return MyInteractions(
      likedPostIds:
          rawLikes is List ? rawLikes.map((e) => '$e').toSet() : const {},
      reactionsByPost: reactions,
    );
  }

  MyInteractions withLike(String postId, bool liked) {
    final next = Set<String>.from(likedPostIds);
    if (liked) {
      next.add(postId);
    } else {
      next.remove(postId);
    }
    return MyInteractions(likedPostIds: next, reactionsByPost: reactionsByPost);
  }

  MyInteractions withReaction(String postId, String emoji, bool on) {
    final next = <String, Set<String>>{
      for (final e in reactionsByPost.entries) e.key: Set<String>.from(e.value),
    };
    final set = next.putIfAbsent(postId, () => <String>{});
    if (on) {
      set.add(emoji);
    } else {
      set.remove(emoji);
      if (set.isEmpty) next.remove(postId);
    }
    return MyInteractions(likedPostIds: likedPostIds, reactionsByPost: next);
  }
}

/// 서비스에서 허용하는 반응 이모지.
/// DB의 `post_reactions.emoji` CHECK 제약과 반드시 같은 목록이어야 한다.
const kReactionEmojis = <String>['🔥', '😮', '😡', '😂', '😢', '🤔'];
