-- hot_score 제거 · 기사 썸네일 추가

-- ── hot_score 제거 ──────────────────────────────────────────────────
--
-- 아무도 계산하지 않아 전부 0이었다. 그런데 클라이언트가 이 컬럼으로 정렬한 뒤
-- 40건을 잘라오는 바람에, 이슈가 157건까지 쌓이자 잘라온 40건 중 31건이
-- 아카이브라서 **화면에 68건 중 9건만 떴다.**
--
-- 채우는 대신 지운다. 화면 순위는 클라이언트가 정렬 모드별로 계산하고,
-- 서버는 "어느 행을 보낼지" 만 고르면 되는데 그건 최신순이면 충분하다.
-- 같은 공식을 서버와 클라이언트 양쪽에서 유지하는 비용을 피하려던
-- 원래 판단(plan.md §7)이 옳았다.
--
-- 항상 0인 컬럼을 남겨두면 다음 사람이 그걸로 정렬한다. 방금 우리가 그랬다.
alter table public.issues drop column if exists hot_score;

-- 관문 정렬에 쓰는 인덱스. 활성 이슈만 최신순으로 훑는다.
create index if not exists issues_live_recent_idx
  on public.issues (last_seen_at desc)
  where status <> 'archived';

-- ── 기사 썸네일 ─────────────────────────────────────────────────────
--
-- 구글 트렌드 RSS 가 `ht:picture` 로 함께 주는 값이다.
-- 추가 요청 없이 이미 파싱하는 응답 안에 들어 있다.
--
-- 주의: 언론사 사진을 gstatic 에서 핫링크하는 구조다.
-- add_plan.md LEGAL-01 법률 검토의 우선 확인 항목.
-- 문제가 되면 컬럼은 두고 클라이언트 표시만 끄면 된다.
alter table public.issues
  add column if not exists image_url text;

comment on column public.issues.image_url is
  '구글 트렌드가 제공하는 기사 썸네일 URL. 이미지를 복제하지 않고 링크만 보관한다.';
