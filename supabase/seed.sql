-- 로컬 개발용 시드
--
-- 이슈만 넣는다. 글/댓글은 author_id 가 auth.users 를 참조하므로 시드로 만들려면
-- 가짜 인증 사용자를 심어야 하는데, auth 스키마는 Supabase 버전마다 컬럼이 달라져서
-- 시드가 쉽게 깨진다. 방은 비어 있는 채로 시작하고, 앱에서 직접 써 보면 된다.
--
-- 화면이 가득 찬 데모를 먼저 보고 싶으면 Supabase 없이 실행하면 된다.
-- (환경변수를 안 주면 앱이 자동으로 목 백엔드로 뜬다 → README 참조)

insert into public.issues
  (keyword, normalized_keyword, summary, status, ranks, related_keywords,
   hot_score, first_seen_at, last_seen_at)
values
  ('한국은행 기준금리', '한국은행기준금리',
   '오전 금통위 발표 직후 관련 검색이 급증했습니다.', 'hot',
   '[{"source":"googleTrends","rank":1,"previous_rank":4,"observed_at":"2026-08-27T09:10:00Z"},
     {"source":"naverNews","rank":2,"previous_rank":5,"observed_at":"2026-08-27T09:10:00Z"},
     {"source":"nate","rank":3,"previous_rank":8,"observed_at":"2026-08-27T09:10:00Z"}]'::jsonb,
   array['금통위','대출금리','부동산'], 86.4, now() - interval '3 hours', now()),

  ('수도권 폭우 특보', '수도권폭우특보',
   '지역별 체감 차이가 커서 제보가 이어지고 있습니다.', 'rising',
   '[{"source":"nate","rank":1,"previous_rank":9,"observed_at":"2026-08-27T09:10:00Z"},
     {"source":"zum","rank":2,"previous_rank":null,"observed_at":"2026-08-27T09:10:00Z"},
     {"source":"googleTrends","rank":5,"previous_rank":12,"observed_at":"2026-08-27T09:10:00Z"}]'::jsonb,
   array['호우경보','지하철 지연','출근길'], 82.1, now() - interval '40 minutes', now()),

  ('월드컵 최종예선', '월드컵최종예선',
   '어제 경기 이후 언급량이 3배 이상 늘었습니다.', 'hot',
   '[{"source":"googleTrends","rank":2,"previous_rank":2,"observed_at":"2026-08-27T09:10:00Z"},
     {"source":"youtube","rank":1,"previous_rank":3,"observed_at":"2026-08-27T09:10:00Z"},
     {"source":"daumNews","rank":4,"previous_rank":6,"observed_at":"2026-08-27T09:10:00Z"}]'::jsonb,
   array['대표팀 명단','중계 시간','승점'], 78.9, now() - interval '14 hours', now()),

  ('전기차 보조금 개편', '전기차보조금개편',
   '공식 발표문이 나오면서 반응이 갈리고 있습니다.', 'steady',
   '[{"source":"naverNews","rank":3,"previous_rank":3,"observed_at":"2026-08-27T09:10:00Z"},
     {"source":"googleTrends","rank":7,"previous_rank":6,"observed_at":"2026-08-27T09:10:00Z"}]'::jsonb,
   array['보조금 신청','충전 인프라'], 61.2, now() - interval '6 hours', now()),

  ('지하철 파업', '지하철파업',
   '협상 결렬 소식이 커뮤니티를 통해 먼저 퍼졌습니다.', 'rising',
   '[{"source":"community","rank":1,"previous_rank":null,"observed_at":"2026-08-27T09:10:00Z"},
     {"source":"nate","rank":6,"previous_rank":14,"observed_at":"2026-08-27T09:10:00Z"}]'::jsonb,
   array['출근길','대체 노선','협상'], 59.7, now() - interval '25 minutes', now()),

  ('아이돌 그룹 컴백', '아이돌그룹컴백',
   '티저 공개 직후 팬덤 유입이 몰렸습니다.', 'steady',
   '[{"source":"youtube","rank":2,"previous_rank":1,"observed_at":"2026-08-27T09:10:00Z"},
     {"source":"zum","rank":4,"previous_rank":4,"observed_at":"2026-08-27T09:10:00Z"}]'::jsonb,
   array['앨범 발매','음원 차트','뮤직비디오'], 54.3, now() - interval '9 hours', now()),

  ('반도체 수출 실적', '반도체수출실적',
   '통계 발표 직후 관련 종목 검색이 함께 늘었습니다.', 'steady',
   '[{"source":"naverNews","rank":5,"previous_rank":7,"observed_at":"2026-08-27T09:10:00Z"}]'::jsonb,
   array['수출입 동향','메모리 가격'], 41.8, now() - interval '5 hours', now()),

  ('태풍 북상', '태풍북상',
   '예상 경로가 갱신되면서 다시 관심이 올라왔습니다.', 'cooling',
   '[{"source":"googleTrends","rank":9,"previous_rank":5,"observed_at":"2026-08-27T09:10:00Z"},
     {"source":"nate","rank":11,"previous_rank":7,"observed_at":"2026-08-27T09:10:00Z"}]'::jsonb,
   array['예상 경로','기상청','항공 결항'], 33.5, now() - interval '20 hours', now() - interval '2 hours'),

  ('프로야구 순위', '프로야구순위',
   '순위 경쟁이 막판으로 가면서 매일 검색되고 있습니다.', 'steady',
   '[{"source":"daumNews","rank":8,"previous_rank":8,"observed_at":"2026-08-27T09:10:00Z"}]'::jsonb,
   array['가을야구','매직넘버'], 28.4, now() - interval '2 days', now() - interval '1 hour'),

  ('아이폰 신제품', '아이폰신제품',
   '공개 일정 루머가 다시 돌기 시작했습니다.', 'cooling',
   '[{"source":"googleTrends","rank":14,"previous_rank":10,"observed_at":"2026-08-27T09:10:00Z"}]'::jsonb,
   array['사전예약','가격','출시일'], 21.0, now() - interval '3 days', now() - interval '5 hours'),

  ('수능 난이도', '수능난이도',
   '모의고사 채점 결과가 공유되며 다시 언급됐습니다.', 'archived',
   '[{"source":"naverNews","rank":16,"previous_rank":12,"observed_at":"2026-08-25T09:10:00Z"}]'::jsonb,
   array['등급컷','모의고사'], 12.3, now() - interval '9 days', now() - interval '4 days'),

  ('부동산 대책 발표', '부동산대책발표',
   '발표 당일 하루 종일 상위권을 유지했습니다.', 'archived',
   '[{"source":"naverNews","rank":1,"previous_rank":1,"observed_at":"2026-08-20T09:10:00Z"},
     {"source":"nate","rank":2,"previous_rank":3,"observed_at":"2026-08-20T09:10:00Z"}]'::jsonb,
   array['전세','공급대책','규제지역'], 9.8, now() - interval '14 days', now() - interval '11 days')

on conflict (normalized_keyword) do nothing;
