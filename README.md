# 핫이슈 (HotIssue)

지금 한국에서 무슨 일이 벌어지는지를 **자체 순위**로 보여주고,
이슈마다 **즉석 토론방**을 열어, **늦게 온 사람도 흐름을 따라잡게** 하는 PWA.

**가입도 로그인도 없다.** 모두 익명으로 참여한다.

---

## 바로 실행하기

Supabase 설정 없이도 앱 전체가 돈다. 목 백엔드로 자동 폴백하기 때문이다.

```powershell
.\run_local.ps1
```

또는 직접:

```bash
flutter pub get
flutter run -d chrome --web-port=8080 --dart-define=FORCE_MOCK=true
```

브라우저에서 http://localhost:8080 이 열린다.
VS Code 라면 실행 패널에서 **핫이슈 (목 데이터, 설정 불필요)** 를 고르면 된다.

## 문서

| 파일 | 내용 |
|---|---|
| [plan.md](plan.md) | 마스터 플랜 — 아키텍처, 랭킹 로직, 데이터 소스, 단계별 계획, 리스크 |
| [idea.md](idea.md) | 아이디어 로그 — 원본 아이디어, 확정/기각 결정과 그 이유, 열린 질문 |
| [add_plan.md](add_plan.md) | 추가 계획 로그 — 무엇을 왜 넣는가 |
| [delete_plan.md](delete_plan.md) | 제거 계획 로그 — 무엇을 언제 왜 빼는가 |
| [supabase/README.md](supabase/README.md) | DB 스키마·RLS·로컬 스택 실행법 |

---

## 익명 설계

계정 제도가 없다는 건 "로그인 버튼을 숨겼다"는 뜻이 아니라, **저장할 계정 정보가 없다**는 뜻이다.

| | |
|---|---|
| 저장하는 것 | 익명 세션 uid 하나 |
| 저장하지 않는 것 | 이메일, 전화번호, 프로필, 표시 이름, 아바타 |
| 닉네임 | `(uid + 방id)` 해시로 매번 생성. 방마다 달라진다 |
| uid의 용도 | ① 자기 글만 삭제 ② 1인 1추천 ③ 도배 차단 |

방마다 닉네임이 바뀌므로 **방을 넘나드는 추적이 불가능하다.** 같은 방 안에서는
같은 이름·같은 색으로 보이므로 대화 맥락은 유지된다.
`post_likes` / `post_reactions` 는 RLS로 본인 행만 조회 가능하다 —
집계 숫자만 공개하고 "누가 무엇에 반응했는지"는 아무도 못 본다.

구현: [anon_identity.dart](lib/core/identity/anon_identity.dart),
[migrations/…_rls.sql](supabase/migrations/20260827000300_rls.sql)

---

## Supabase 연결

### 1. 프로젝트 준비

로컬 스택(Docker 필요):

```bash
supabase start
supabase db reset
```

또는 클라우드 프로젝트:

```bash
supabase login
supabase link --project-ref <PROJECT_REF>
supabase db push
```

> 클라우드는 대시보드에서 **Authentication → Anonymous sign-ins** 를 켜야 한다.

### 2. 키 넣기

```powershell
Copy-Item env\dev.example.json env\dev.json
# env\dev.json 에 SUPABASE_URL, SUPABASE_ANON_KEY 채우기
```

### 3. 실행

```powershell
.\run_local.ps1 -Supabase
```

설정이 없거나 초기화가 실패하면 콘솔에 이유를 찍고 목 백엔드로 뜬다.
백엔드가 없다고 화면을 못 보는 상황은 만들지 않았다.
현재 어느 백엔드로 도는지는 **설정 탭 상단**과 순위 화면 하단에 표시된다.

---

## Git

```bash
git init
git add .
git commit -m "핫이슈 Phase 0-1: Flutter PWA 스캐폴드 + Supabase 익명 백엔드"
git branch -M main
git remote add origin <저장소 URL>
git push -u origin main
```

- [.gitignore](.gitignore) — `env/*.json`(Supabase 키), 빌드 산출물, Supabase 로컬 상태 제외
- [.gitattributes](.gitattributes) — 줄바꿈 정규화. Windows/CI 혼용 시 diff 오염 방지
- [.github/workflows/ci.yml](.github/workflows/ci.yml) — analyze · test · 웹 빌드 +
  로컬 Supabase 스택에 마이그레이션/시드를 실제로 적용해 RLS 오타까지 잡는다

> CI의 `dart format` 단계는 지금 `continue-on-error` 다.
> 한 번 `dart format .` 을 돌린 뒤 차단 단계로 승격시킬 것 → [add_plan.md](add_plan.md) `CI-01`

---

## MCP

[.mcp.json](.mcp.json) 에 Supabase MCP 서버가 정의되어 있다.
연결하면 Claude Code 안에서 스키마 조회·마이그레이션 확인·로그 열람을 할 수 있다.

토큰은 파일에 넣지 않는다. 환경변수로 주입한다.

```powershell
# 사용자 환경변수에 등록 (새 터미널부터 적용)
setx SUPABASE_ACCESS_TOKEN "sbp_xxxxxxxxxxxx"
setx SUPABASE_PROJECT_REF  "your-project-ref"
```

- 액세스 토큰: Supabase 대시보드 → Account → Access Tokens
- 프로젝트 ref: 프로젝트 URL `https://<ref>.supabase.co` 의 `<ref>`

환경변수를 넣은 뒤 Claude Code를 이 폴더에서 다시 시작하면 `.mcp.json` 승인 프롬프트가 뜬다.
`/mcp` 로 연결 상태를 확인할 수 있다.

`--read-only` 로 잠가 뒀다. 마이그레이션 실행 같은 쓰기 작업은 `supabase` CLI로 한다.

---

## 구조

```
lib/
├─ main.dart                        진입점 · 익명 세션 생성
├─ app.dart                         MaterialApp.router
├─ core/
│  ├─ config/app_config.dart        --dart-define 설정 · 목 폴백 판단
│  ├─ backend/backend_bootstrap.dart Supabase 초기화 + 익명 로그인
│  ├─ identity/anon_identity.dart   ★ 방별 익명 닉네임 생성
│  ├─ router/app_router.dart        go_router (해시 URL)
│  └─ theme/app_theme.dart          다크 테마 · 색 토큰 · 포맷 헬퍼
├─ domain/
│  ├─ models/                       Issue · Post · Comment · MyInteractions
│  └─ ranking/
│     ├─ hot_score.dart             ★ 자체 정렬 엔진
│     └─ ranked_issue.dart          정렬 결과 · 모드 프리셋
├─ data/
│  ├─ mock/mock_feed.dart           목 데이터 생성기
│  └─ repositories/
│     ├─ issue_repository.dart      인터페이스
│     ├─ mock_issue_repository.dart 인메모리 구현
│     └─ supabase_issue_repository.dart  Postgres + Realtime 구현
├─ state/providers.dart             Riverpod 배선 · 백엔드 교체 지점
└─ features/
   ├─ home/       하단 탭
   ├─ trending/   실시간 순위 · 점수 근거 시트
   ├─ room/       이슈방 · Catch-up 카드 · 작성창
   ├─ archive/    지난 이슈
   └─ me/         익명 안내 · 정렬 기준 · 소스 목록

supabase/
├─ migrations/    스키마 · 함수 · RLS
├─ seed.sql       로컬 개발용 이슈 12건
└─ config.toml    익명 로그인만 활성화
```

## 핵심 로직 한눈에

```
HotScore = ( 0.35·순위 + 0.25·상승세 + 0.15·확산도 + 0.25·참여도 ) × 신선도 × 100
```

- **확산도**가 어뷰징 방어의 핵심이다. 한 사이트를 조작하긴 쉽지만 8개 소스에 동시에 띄우긴 어렵다.
- **참여도**가 우리만의 신호다. 이게 없으면 우리는 포털의 미러 사이트일 뿐이다.
- **신선도**는 곱셈 항이다. 안 넣으면 오래된 이슈가 영원히 상단에 남는다.

계산 근거는 앱에서 그대로 공개한다 (카드의 점수를 탭). 설계 의도는 [plan.md §5](plan.md).

## 백엔드 교체 지점

[lib/state/providers.dart](lib/state/providers.dart):

```dart
final issueRepositoryProvider = Provider<IssueRepository>((ref) {
  if (ref.watch(backendReadyProvider)) {
    return SupabaseIssueRepository(Supabase.instance.client);
  }
  final repo = MockIssueRepository();
  ref.onDispose(repo.dispose);
  return repo;
});
```

UI와 도메인 로직은 `IssueRepository` 인터페이스만 안다.

## 알려진 제약

- **수집기가 없다.** `issues` 테이블에 쓰는 주체가 아직 없어서 순위는 시드가 전부다 (Phase 3).
- **live_users 는 항상 0.** Realtime Presence 미연동 → [add_plan.md](add_plan.md) `INFRA-03`
- **이미지 업로드 미구현.** 버킷·RLS는 준비됐고 클라이언트 코드만 없다.
- **매니페스트 아이콘이 SVG.** 배포 전 PNG 교체 필요 → [add_plan.md](add_plan.md) `PWA-01`
- **네이티브 플랫폼 폴더 없음.** 필요하면
  `flutter create . --platforms=android,ios --org kr.hotissue` (기존 `web/` 은 안 건드림)
