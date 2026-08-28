-- 기사 브리핑
--
-- 사용자가 방에 들어가도 헤드라인만 보이고 내용을 알 수 없었다.
-- 원인은 두 가지였다.
--
-- 1. 구글 트렌드의 `ht:news_item_snippet` 이 늘 비어 있다(확인: 30건 전부 0자).
--    `summary` 는 `newsSnippet ?? newsTitle` 로 폴백해서 계속 **기사 제목**이 들어갔다.
-- 2. 정작 언론사 RSS 의 <description> 에 기사 리드가 83~497자씩 오는데
--    파서가 <title> 만 읽고 버리고 있었다.
--
-- 이 컬럼은 매칭된 기사들을 담는다. 리드는 **언론사가 배포 목적으로 피드에 넣은 값**이고
-- 표준 RSS 리더가 그대로 보여주는 값이다. 기사 본문을 긁어오는 것과는 다르다
-- (plan.md §6.2 의 선을 넘지 않는다).
--
--   [{ "outlet": "yna", "outlet_label": "연합뉴스",
--      "title": "...", "summary": "기사 리드 …",
--      "url": "https://…", "origin": "rss" | "trends",
--      "published_at": "..." }]
--
-- 왜 별도 테이블이 아니라 jsonb 인가: `ranks` 와 같은 이유다.
-- Realtime `.stream()` 은 조인을 지원하지 않으므로 카드에 필요한 값은 한 행에 있어야 한다.
alter table public.issues
  add column if not exists articles jsonb not null default '[]'::jsonb;

comment on column public.issues.articles is
  '언론사 RSS 와 구글 트렌드에서 모은 관련 기사. 본문이 아니라 피드가 제공한 리드와 링크만 보관한다. '
  '표시할 때 언론사명과 원문 링크를 반드시 함께 노출할 것.';
