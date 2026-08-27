-- RLS 정책 + Realtime 발행
--
-- 원칙
--  1. 읽기는 전부 공개(anon 포함). 이슈와 대화는 로그인 없이 보이는 게 서비스 전제다.
--  2. 쓰기는 authenticated(= 익명 로그인 완료) 만.
--  3. 카운터/블라인드/고정 필드는 클라이언트가 못 건드린다 → UPDATE 정책을 아예 안 만든다.
--  4. 추천/반응 행은 **본인 것만 조회 가능**. 누가 무엇에 반응했는지는 익명성의 핵심이라
--     집계 숫자(비정규화 컬럼)만 공개하고 원본 행은 감춘다.

alter table public.issues          enable row level security;
alter table public.rank_snapshots  enable row level security;
alter table public.posts           enable row level security;
alter table public.comments        enable row level security;
alter table public.post_likes      enable row level security;
alter table public.post_reactions  enable row level security;
alter table public.reports         enable row level security;

-- ── 이슈: 읽기만 공개. 쓰기는 service_role(수집기) 전용 ─────────────
drop policy if exists "issues_select_all" on public.issues;
create policy "issues_select_all"
  on public.issues for select
  to anon, authenticated
  using (true);

-- ── 수집 이력: 클라이언트 접근 없음 (정책을 만들지 않는다) ──────────

-- ── 글 ──────────────────────────────────────────────────────────────
drop policy if exists "posts_select_all" on public.posts;
create policy "posts_select_all"
  on public.posts for select
  to anon, authenticated
  using (true);

drop policy if exists "posts_insert_own" on public.posts;
create policy "posts_insert_own"
  on public.posts for insert
  to authenticated
  with check (
    author_id = auth.uid()
    and is_pinned = false      -- 고정은 운영자만
    and is_hidden = false
    and likes_count = 0        -- 카운터를 미리 부풀려서 넣지 못하게
    and comments_count = 0
    and report_count = 0
  );

drop policy if exists "posts_delete_own" on public.posts;
create policy "posts_delete_own"
  on public.posts for delete
  to authenticated
  using (author_id = auth.uid());

-- UPDATE 정책 없음 = 수정 불가. 익명 서비스에서 사후 수정은
-- "추천 받은 뒤 내용 바꾸기" 어뷰징 통로가 된다.

-- ── 댓글 ────────────────────────────────────────────────────────────
drop policy if exists "comments_select_all" on public.comments;
create policy "comments_select_all"
  on public.comments for select
  to anon, authenticated
  using (true);

drop policy if exists "comments_insert_own" on public.comments;
create policy "comments_insert_own"
  on public.comments for insert
  to authenticated
  with check (author_id = auth.uid() and is_hidden = false and likes_count = 0);

drop policy if exists "comments_delete_own" on public.comments;
create policy "comments_delete_own"
  on public.comments for delete
  to authenticated
  using (author_id = auth.uid());

-- ── 추천: 내 것만 보이고, 내 것만 만들고 지울 수 있다 ───────────────
drop policy if exists "post_likes_select_own" on public.post_likes;
create policy "post_likes_select_own"
  on public.post_likes for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "post_likes_insert_own" on public.post_likes;
create policy "post_likes_insert_own"
  on public.post_likes for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "post_likes_delete_own" on public.post_likes;
create policy "post_likes_delete_own"
  on public.post_likes for delete
  to authenticated
  using (user_id = auth.uid());

-- ── 이모지 반응: 동일 ───────────────────────────────────────────────
drop policy if exists "post_reactions_select_own" on public.post_reactions;
create policy "post_reactions_select_own"
  on public.post_reactions for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "post_reactions_insert_own" on public.post_reactions;
create policy "post_reactions_insert_own"
  on public.post_reactions for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "post_reactions_delete_own" on public.post_reactions;
create policy "post_reactions_delete_own"
  on public.post_reactions for delete
  to authenticated
  using (user_id = auth.uid());

-- ── 신고: 넣을 수만 있고, 내가 넣은 것만 보인다 ─────────────────────
drop policy if exists "reports_insert_own" on public.reports;
create policy "reports_insert_own"
  on public.reports for insert
  to authenticated
  with check (reporter_id = auth.uid() and resolved = false);

drop policy if exists "reports_select_own" on public.reports;
create policy "reports_select_own"
  on public.reports for select
  to authenticated
  using (reporter_id = auth.uid());

-- ── 이미지 스토리지 ─────────────────────────────────────────────────
-- 경로 규약: post-images/{uid}/{uuid}.webp
-- 첫 번째 폴더가 본인 uid 여야만 업로드 가능 → 남의 폴더 오염 차단
drop policy if exists "post_images_read" on storage.objects;
create policy "post_images_read"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'post-images');

drop policy if exists "post_images_insert_own" on storage.objects;
create policy "post_images_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "post_images_delete_own" on storage.objects;
create policy "post_images_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ── Realtime 발행 ───────────────────────────────────────────────────
-- 구독자에게도 RLS가 적용되므로, 읽기가 공개인 세 테이블만 올린다.
-- post_likes / post_reactions 는 본인 것만 보이므로 스트림에 올려봐야 의미가 없고,
-- 대신 posts 의 비정규화 카운터가 갱신되면서 같은 효과를 낸다.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and tablename = 'issues'
  ) then
    alter publication supabase_realtime add table public.issues;
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and tablename = 'posts'
  ) then
    alter publication supabase_realtime add table public.posts;
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and tablename = 'comments'
  ) then
    alter publication supabase_realtime add table public.comments;
  end if;
end
$$;
