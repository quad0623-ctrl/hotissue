-- 수집 자동 실행.
--
-- 이전에는 로컬 Dart 수집기가 이 일을 했다. 그러면 배포본의 순위가
-- 누군가의 PC 전원에 묶인다. pg_cron 이 Edge Function 을 깨우는 구조로 옮긴다.
--
-- service_role 키는 Vault 에 넣어 두고 이름으로만 참조한다.
-- cron.job 테이블은 평문으로 조회되므로 여기에 키를 박으면 안 된다.
-- 키 등록은 마이그레이션이 아니라 배포 절차에서 한 번 수행한다:
--   select vault.create_secret('<service_role_key>', 'collect_service_key', '...');

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net  with schema extensions;

-- 재적용해도 중복 등록되지 않도록 먼저 지운다
select cron.unschedule('collect-trends')
where exists (select 1 from cron.job where jobname = 'collect-trends');

-- 5분 주기.
-- 구글 트렌드는 분 단위로 갱신되지만, 언론사 피드 19개를 매번 읽으므로
-- 더 짧게 잡으면 소스에 부담이 된다 (plan.md §6.2 — 최소 60초 간격).
select cron.schedule(
  'collect-trends',
  '*/5 * * * *',
  $$
  select net.http_post(
    url     := 'https://flwupjrspntmczzpgtiy.supabase.co/functions/v1/collect',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'collect_service_key'
      )
    ),
    timeout_milliseconds := 120000
  );
  $$
);
