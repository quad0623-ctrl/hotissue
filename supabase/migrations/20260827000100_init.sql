-- 핫이슈 초기 스키마
--
-- 설계 전제: **계정 제도가 없다.** 모든 사용자는 Supabase 익명 인증(anonymous sign-in)으로
-- auth.users 행 하나를 받는다. 프로필 테이블도, 이메일도, 표시 이름도 저장하지 않는다.
-- auth.uid()는 오직 세 가지 용도로만 쓴다:
--   1) 자기 글만 지울 수 있게 (RLS)
--   2) 추천/반응 1인 1회 보장 (복합 PK)
--   3) 도배 차단 (레이트 리밋 트리거)
-- 닉네임은 클라이언트가 (uid + 방id) 해시로 만들어 넣는다. 방마다 달라지므로
-- 방을 넘나드는 추적이 불가능하다.

create extension if not exists "pgcrypto";

-- ── 이슈 ────────────────────────────────────────────────────────────
-- ranks 는 현재 스냅샷을 통째로 들고 있는 jsonb 배열이다.
-- 조인 없이 .stream() 한 번으로 카드에 필요한 모든 값이 나오게 하려는 의도.
--   [{"source":"googleTrends","rank":3,"previous_rank":7,"observed_at":"2026-08-27T..."}]
create table if not exists public.issues (
  id                  uuid primary key default gen_random_uuid(),
  keyword             text not null,
  normalized_keyword  text not null,
  aliases             text[] not null default '{}',
  summary             text,
  status              text not null default 'steady'
                        check (status in ('rising','hot','steady','cooling','archived')),
  ranks               jsonb not null default '[]'::jsonb,
  related_keywords    text[] not null default '{}',

  -- 카운터는 트리거가 관리한다. 클라이언트 쓰기 금지(RLS에 update 정책 없음).
  posts_count         integer not null default 0,
  comments_count      integer not null default 0,
  likes_count         integer not null default 0,
  reactions_count     integer not null default 0,
  live_users          integer not null default 0,

  -- 서버가 계산한 권위 점수. 클라이언트는 정렬 모드에 따라 로컬 재계산도 한다.
  hot_score           numeric(6,2) not null default 0,

  first_seen_at       timestamptz not null default now(),
  last_seen_at        timestamptz not null default now(),
  created_at          timestamptz not null default now()
);

create unique index if not exists issues_normalized_keyword_key
  on public.issues (normalized_keyword);
create index if not exists issues_status_idx      on public.issues (status);
create index if not exists issues_last_seen_idx   on public.issues (last_seen_at desc);
create index if not exists issues_hot_score_idx   on public.issues (hot_score desc);

-- ── 순위 수집 이력 (클라이언트는 읽지 않음) ──────────────────────────
-- 수집기가 append 만 한다. 90일 후 폐기 → delete_plan.md DATA-DEL-01
create table if not exists public.rank_snapshots (
  id            bigserial primary key,
  issue_id      uuid not null references public.issues(id) on delete cascade,
  source        text not null,
  rank          integer not null,
  previous_rank integer,
  observed_at   timestamptz not null default now()
);

create index if not exists rank_snapshots_issue_idx
  on public.rank_snapshots (issue_id, observed_at desc);

-- ── 글 ──────────────────────────────────────────────────────────────
create table if not exists public.posts (
  id              uuid primary key default gen_random_uuid(),
  issue_id        uuid not null references public.issues(id) on delete cascade,
  author_id       uuid not null default auth.uid()
                    references auth.users(id) on delete cascade,

  -- 익명 표시용. 방마다 다른 값이 들어온다 (AnonIdentity 참조)
  nickname        text not null,
  color_seed      integer not null default 0,

  body            text,
  image_path      text,

  likes_count     integer not null default 0,
  comments_count  integer not null default 0,
  reaction_counts jsonb   not null default '{}'::jsonb,
  report_count    integer not null default 0,

  is_pinned       boolean not null default false,
  is_hidden       boolean not null default false,
  created_at      timestamptz not null default now(),

  constraint posts_content_present check (body is not null or image_path is not null),
  constraint posts_body_len        check (body is null or char_length(body) <= 500),
  constraint posts_nickname_len    check (char_length(nickname) between 1 and 24)
);

create index if not exists posts_issue_created_idx on public.posts (issue_id, created_at);
create index if not exists posts_author_recent_idx on public.posts (author_id, created_at desc);

-- ── 댓글 ────────────────────────────────────────────────────────────
-- issue_id 를 비정규화해 둔다. 방 단위 조회/삭제가 잦아서.
create table if not exists public.comments (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.posts(id) on delete cascade,
  issue_id    uuid not null references public.issues(id) on delete cascade,
  author_id   uuid not null default auth.uid()
                references auth.users(id) on delete cascade,
  nickname    text not null,
  color_seed  integer not null default 0,
  body        text not null check (char_length(body) between 1 and 300),
  likes_count integer not null default 0,
  is_hidden   boolean not null default false,
  created_at  timestamptz not null default now()
);

create index if not exists comments_post_created_idx on public.comments (post_id, created_at);

-- ── 추천 ────────────────────────────────────────────────────────────
-- (post_id, user_id) 복합 PK = 1인 1추천이 스키마 레벨에서 보장된다.
create table if not exists public.post_likes (
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null default auth.uid()
               references auth.users(id) on delete cascade,
  issue_id   uuid not null references public.issues(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists post_likes_mine_idx on public.post_likes (issue_id, user_id);

-- ── 이모지 반응 ─────────────────────────────────────────────────────
create table if not exists public.post_reactions (
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null default auth.uid()
               references auth.users(id) on delete cascade,
  issue_id   uuid not null references public.issues(id) on delete cascade,
  emoji      text not null check (emoji in ('🔥','😮','😡','😂','😢','🤔')),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id, emoji)
);

create index if not exists post_reactions_mine_idx on public.post_reactions (issue_id, user_id);

-- ── 신고 ────────────────────────────────────────────────────────────
-- 익명 서비스에서 신고는 유일한 자정 장치다. 동시에 신고 자체가 공격 수단이
-- 될 수 있으므로 (대상, 신고자) 유니크로 중복 신고를 막는다.
create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in ('post','comment','issue')),
  target_id   uuid not null,
  reporter_id uuid not null default auth.uid()
                references auth.users(id) on delete cascade,
  reason      text not null check (char_length(reason) <= 200),
  resolved    boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (target_type, target_id, reporter_id)
);

-- ── 이미지 버킷 ─────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('post-images', 'post-images', true)
on conflict (id) do nothing;
