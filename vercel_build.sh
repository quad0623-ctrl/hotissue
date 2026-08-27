#!/usr/bin/env bash
# Vercel 빌드 스크립트.
#
# Vercel 빌드 이미지에는 Flutter 가 없다. stable 채널을 얕게 클론해서 쓴다.
# 첫 빌드는 SDK 내려받느라 5~8분 걸리고, 이후에는 빌드 캐시가 있으면 빨라진다.
set -euo pipefail

FLUTTER_DIR="${PWD}/_flutter"
FLUTTER="${FLUTTER_DIR}/bin/flutter"

# ── 필수 환경변수 확인 ────────────────────────────────────────────
# 값이 없으면 앱이 목 백엔드로 폴백한다. 로컬에서는 그게 편의지만
# 배포본에서는 **가짜 데이터가 진짜처럼 보이는 사고**가 된다. 차라리 빌드를 세운다.
missing=0
for v in SUPABASE_URL SUPABASE_PUBLISHABLE_KEY; do
  if [ -z "${!v:-}" ]; then
    echo "환경변수 $v 가 없습니다." >&2
    missing=1
  fi
done
if [ "$missing" = "1" ]; then
  cat >&2 <<'MSG'

Vercel 프로젝트 설정 → Settings → Environment Variables 에 아래를 넣으세요.

  SUPABASE_URL              https://<project-ref>.supabase.co
  SUPABASE_PUBLISHABLE_KEY  sb_publishable_...

publishable key 는 클라이언트에 실려도 되는 값입니다 (RLS 로 보호됨).
service_role 키는 절대 넣지 마세요.
MSG
  exit 1
fi

# ── Flutter SDK ──────────────────────────────────────────────────
if [ ! -d "$FLUTTER_DIR" ]; then
  echo "Flutter stable 클론 중…"
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$FLUTTER_DIR"
fi

# 빌드 컨테이너는 root 로 도는데 Flutter 가 소유자 불일치를 문제 삼는다
git config --global --add safe.directory "$FLUTTER_DIR" || true

export PATH="${FLUTTER_DIR}/bin:${PATH}"

"$FLUTTER" --version
"$FLUTTER" config --enable-web --no-analytics
"$FLUTTER" pub get

# ── 웹 빌드 ──────────────────────────────────────────────────────
# COLLECTOR_URL 은 넘기지 않는다. 수집기는 로컬 프로세스라 배포본에서 접근 불가다.
# 넘기면 앱이 localhost 를 폴링하다 실패한다.
"$FLUTTER" build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"

echo "빌드 완료 → build/web"
ls -la build/web | head -20
