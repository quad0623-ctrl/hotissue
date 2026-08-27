-- 카운터 트리거 · 레이트 리밋 · 토글 RPC
--
-- 카운터 트리거는 모두 security definer 다. 소유자(postgres)가 RLS를 우회하므로
-- 클라이언트에 posts/issues UPDATE 권한을 주지 않고도 카운터를 갱신할 수 있다.
-- 반대로 토글 RPC 는 security invoker 다. 호출자의 RLS가 그대로 적용되어야
-- 남의 이름으로 추천을 누를 수 없다.

-- ── 글 수 ───────────────────────────────────────────────────────────
create or replace function public.on_post_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.issues
       set posts_count = posts_count + 1,
           last_seen_at = greatest(last_seen_at, now())
     where id = new.issue_id;
  elsif tg_op = 'DELETE' then
    update public.issues
       set posts_count = greatest(posts_count - 1, 0)
     where id = old.issue_id;
  end if;
  return null;
end;
$$;

drop trigger if exists posts_count_trg on public.posts;
create trigger posts_count_trg
  after insert or delete on public.posts
  for each row execute function public.on_post_change();

-- ── 댓글 수 (글과 이슈 양쪽) ────────────────────────────────────────
create or replace function public.on_comment_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts  set comments_count = comments_count + 1 where id = new.post_id;
    update public.issues set comments_count = comments_count + 1 where id = new.issue_id;
  elsif tg_op = 'DELETE' then
    update public.posts  set comments_count = greatest(comments_count - 1, 0) where id = old.post_id;
    update public.issues set comments_count = greatest(comments_count - 1, 0) where id = old.issue_id;
  end if;
  return null;
end;
$$;

drop trigger if exists comments_count_trg on public.comments;
create trigger comments_count_trg
  after insert or delete on public.comments
  for each row execute function public.on_comment_change();

-- ── 추천 수 ─────────────────────────────────────────────────────────
create or replace function public.on_like_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts  set likes_count = likes_count + 1 where id = new.post_id;
    update public.issues set likes_count = likes_count + 1 where id = new.issue_id;
  elsif tg_op = 'DELETE' then
    update public.posts  set likes_count = greatest(likes_count - 1, 0) where id = old.post_id;
    update public.issues set likes_count = greatest(likes_count - 1, 0) where id = old.issue_id;
  end if;
  return null;
end;
$$;

drop trigger if exists post_likes_count_trg on public.post_likes;
create trigger post_likes_count_trg
  after insert or delete on public.post_likes
  for each row execute function public.on_like_change();

-- ── 이모지 반응 수 (posts.reaction_counts jsonb 증감) ───────────────
create or replace function public.on_reaction_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  current_count integer;
begin
  if tg_op = 'INSERT' then
    update public.posts
       set reaction_counts = jsonb_set(
             reaction_counts,
             array[new.emoji],
             to_jsonb(coalesce((reaction_counts ->> new.emoji)::integer, 0) + 1),
             true)
     where id = new.post_id;

    update public.issues set reactions_count = reactions_count + 1 where id = new.issue_id;

  elsif tg_op = 'DELETE' then
    select coalesce((reaction_counts ->> old.emoji)::integer, 0)
      into current_count
      from public.posts where id = old.post_id;

    -- 0이 되면 키 자체를 지운다. 안 그러면 "🔥 0" 이 화면에 남는다.
    update public.posts
       set reaction_counts = case
             when current_count <= 1 then reaction_counts - old.emoji
             else jsonb_set(reaction_counts, array[old.emoji],
                            to_jsonb(current_count - 1), true)
           end
     where id = old.post_id;

    update public.issues
       set reactions_count = greatest(reactions_count - 1, 0)
     where id = old.issue_id;
  end if;
  return null;
end;
$$;

drop trigger if exists post_reactions_count_trg on public.post_reactions;
create trigger post_reactions_count_trg
  after insert or delete on public.post_reactions
  for each row execute function public.on_reaction_change();

-- ── 도배 차단 ───────────────────────────────────────────────────────
-- 계정이 없으니 "가입 후 N일" 같은 장치를 쓸 수 없다. 시간당 속도로만 막는다.
create or replace function public.enforce_post_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recent integer;
begin
  select count(*) into recent
    from public.posts
   where author_id = new.author_id
     and created_at > now() - interval '10 seconds';

  if recent >= 3 then
    raise exception '너무 빠르게 작성하고 있습니다. 잠시 후 다시 시도해주세요.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists posts_rate_limit_trg on public.posts;
create trigger posts_rate_limit_trg
  before insert on public.posts
  for each row execute function public.enforce_post_rate_limit();

-- ── 신고 누적 시 자동 블라인드 ──────────────────────────────────────
-- 정보통신망법 제44조의2 대응의 1차 자동화. 운영자 검토는 Phase 5.
create or replace function public.on_report_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  total integer;
begin
  select count(*) into total
    from public.reports
   where target_type = new.target_type and target_id = new.target_id;

  if new.target_type = 'post' then
    update public.posts
       set report_count = total,
           is_hidden = (total >= 5)
     where id = new.target_id;
  elsif new.target_type = 'comment' then
    update public.comments
       set is_hidden = (total >= 5)
     where id = new.target_id;
  end if;

  return null;
end;
$$;

drop trigger if exists reports_autohide_trg on public.reports;
create trigger reports_autohide_trg
  after insert on public.reports
  for each row execute function public.on_report_created();

-- ── 추천 토글 ───────────────────────────────────────────────────────
-- 클라이언트가 "지금 눌렀나 안 눌렀나"를 몰라도 되게 서버에서 원자적으로 뒤집는다.
-- 반환값 = 토글 후 상태(true = 추천함)
create or replace function public.toggle_post_like(p_post_id uuid)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_issue   uuid;
  v_deleted integer;
begin
  if auth.uid() is null then
    raise exception '익명 세션이 없습니다' using errcode = 'P0001';
  end if;

  delete from public.post_likes
   where post_id = p_post_id and user_id = auth.uid();
  get diagnostics v_deleted = row_count;
  if v_deleted > 0 then
    return false;
  end if;

  select issue_id into v_issue from public.posts where id = p_post_id;
  if v_issue is null then
    raise exception '글을 찾을 수 없습니다' using errcode = 'P0001';
  end if;

  insert into public.post_likes (post_id, user_id, issue_id)
  values (p_post_id, auth.uid(), v_issue);
  return true;
end;
$$;

-- ── 이모지 반응 토글 ────────────────────────────────────────────────
create or replace function public.toggle_post_reaction(p_post_id uuid, p_emoji text)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_issue   uuid;
  v_deleted integer;
begin
  if auth.uid() is null then
    raise exception '익명 세션이 없습니다' using errcode = 'P0001';
  end if;

  delete from public.post_reactions
   where post_id = p_post_id and user_id = auth.uid() and emoji = p_emoji;
  get diagnostics v_deleted = row_count;
  if v_deleted > 0 then
    return false;
  end if;

  select issue_id into v_issue from public.posts where id = p_post_id;
  if v_issue is null then
    raise exception '글을 찾을 수 없습니다' using errcode = 'P0001';
  end if;

  insert into public.post_reactions (post_id, user_id, issue_id, emoji)
  values (p_post_id, auth.uid(), v_issue, p_emoji);
  return true;
end;
$$;

-- ── 내가 이 방에서 누른 것들 ────────────────────────────────────────
-- 방에 들어올 때 한 번 호출해서 하이라이트 상태를 복원한다.
-- 남의 추천 목록은 RLS로 막혀 있으므로 이 함수로도 내 것만 나온다.
--   { "likes": ["postId", ...], "reactions": { "postId": ["🔥","😮"] } }
create or replace function public.my_room_interactions(p_issue_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select jsonb_build_object(
    'likes', coalesce(
      (select jsonb_agg(post_id)
         from public.post_likes
        where issue_id = p_issue_id and user_id = auth.uid()),
      '[]'::jsonb),
    'reactions', coalesce(
      (select jsonb_object_agg(post_id, emojis)
         from (select post_id::text as post_id, jsonb_agg(emoji) as emojis
                 from public.post_reactions
                where issue_id = p_issue_id and user_id = auth.uid()
                group by post_id) grouped),
      '{}'::jsonb)
  );
$$;
