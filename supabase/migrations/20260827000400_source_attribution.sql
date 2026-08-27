-- 원문 기사 출처.
--
-- 구글 트렌드 RSS 가 키워드와 함께 관련 기사(제목·언론사·URL·요약)와
-- 대략적 검색량을 준다. 덕분에 요약을 우리가 지어낼 필요가 없고,
-- 본문을 복제하는 대신 원문 링크를 걸 수 있어 저작권 측면에서도 안전하다.
-- (plan.md §6.2 — "키워드만 수집하고 원문 링크만 건다")
alter table public.issues
  add column if not exists source_title   text,
  add column if not exists source_url     text,
  add column if not exists source_outlet  text,
  add column if not exists approx_traffic text;

comment on column public.issues.source_url is
  '원문 기사 링크. 본문은 저장하지 않는다.';
comment on column public.issues.approx_traffic is
  '구글 트렌드가 주는 대략적 검색량 (예: 2000+). 정확한 수치가 아니다.';
