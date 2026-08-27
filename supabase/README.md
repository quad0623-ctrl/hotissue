# Supabase 설정

## 무엇이 들어 있나

| 파일 | 내용 |
|---|---|
| `migrations/20260827000100_init.sql` | 테이블·인덱스·스토리지 버킷 |
| `migrations/20260827000200_functions.sql` | 카운터 트리거, 도배 차단, 신고 자동 블라인드, 토글 RPC |
| `migrations/20260827000300_rls.sql` | RLS 정책, Realtime 발행 |
| `seed.sql` | 이슈 12건 (로컬 개발용) |
| `config.toml` | 로컬 스택 설정. **익명 로그인만 켜져 있고 이메일/SMS 가입은 꺼져 있다** |

## 계정이 없다는 게 스키마에 어떻게 반영되어 있나

프로필 테이블이 없다. 이메일도, 표시 이름도, 아바타도 저장하지 않는다.
`auth.users` 행은 익명 로그인으로 자동 생성되고, `auth.uid()` 는 딱 세 가지에만 쓴다.

1. **자기 글만 삭제** — `posts_delete_own` 정책
2. **1인 1추천** — `post_likes` 의 복합 기본키 `(post_id, user_id)`
3. **도배 차단** — `enforce_post_rate_limit` 트리거 (10초에 3건)

닉네임은 클라이언트가 `(uid + 방id)` 해시로 만들어 글 행에 박아 넣는다
([anon_identity.dart](../lib/core/identity/anon_identity.dart)).
서버는 이 값을 검증하지 않는다 — 검증하려면 uid와 닉네임의 연결을 저장해야 하는데,
그게 바로 만들지 않기로 한 것이기 때문이다.

`post_likes` 와 `post_reactions` 는 **본인 행만 조회 가능**하다.
누가 무엇에 반응했는지는 익명성의 핵심이라, 집계 숫자만 공개하고 원본은 감춘다.

## 로컬에서 돌리기

Docker Desktop 이 켜져 있어야 한다.

```bash
npm i -g supabase          # 또는 scoop install supabase
supabase start             # 첫 실행은 이미지 내려받느라 몇 분 걸린다
supabase db reset          # 마이그레이션 + 시드 적용
```

`supabase start` 가 출력하는 `API URL` 과 `anon key` 를 `env/dev.json` 에 넣는다.

```bash
supabase stop              # 종료
supabase stop --no-backup  # 데이터까지 초기화
```

Studio: http://localhost:54323

## 클라우드 프로젝트에 배포하기

```bash
supabase login
supabase link --project-ref <PROJECT_REF>
supabase db push
```

시드는 클라우드에 자동 적용되지 않는다. 필요하면 Studio SQL Editor 에서
`seed.sql` 내용을 직접 실행한다.

**대시보드에서 익명 로그인을 켜야 한다**:
Authentication → Sign In / Providers → Anonymous sign-ins → 활성화.
이걸 안 켜면 앱이 세션을 못 만들고 목 백엔드로 폴백한다.

## 방이 비어 있는 이유

시드에는 이슈만 있고 글이 없다. 글은 `author_id` 가 `auth.users` 를 참조하는데,
가짜 인증 사용자를 심으려면 `auth` 스키마를 직접 건드려야 하고 그건 Supabase
버전이 바뀔 때마다 깨진다. 방에 직접 글을 써 보면 된다.

화면이 가득 찬 데모를 먼저 보고 싶으면 목 백엔드로 실행하면 된다.

```
flutter run -d chrome --dart-define=FORCE_MOCK=true
```

## 아직 없는 것

- **수집기**: `issues` 테이블에 쓰는 주체가 없다. 지금은 시드가 전부다.
  Phase 3에서 Edge Function + `pg_cron` 으로 붙인다 → [add_plan.md](../add_plan.md) `DATA-01`
- **live_users**: 컬럼만 있고 항상 0이다. Realtime Presence 연동은
  [add_plan.md](../add_plan.md) `INFRA-03`
- **이미지 업로드**: 버킷과 정책은 만들어 뒀지만 클라이언트 업로드 코드가 없다.
