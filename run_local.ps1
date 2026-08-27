# 로컬 실행 헬퍼 (Windows PowerShell)
#
#   .\run_local.ps1              → 목 데이터로 실행 (Supabase 설정 불필요)
#   .\run_local.ps1 -Supabase    → env/dev.json 의 Supabase 프로젝트로 실행
#   .\run_local.ps1 -Test        → 테스트만 실행
#   .\run_local.ps1 -Port 5000   → 포트 지정
#   .\run_local.ps1 -Device edge → 브라우저 지정 (기본: 설치된 것을 자동 선택)

param(
    [switch]$Supabase,
    [switch]$Test,
    [int]$Port = 8080,
    [string]$Device = ''
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

# TEMP 가 깨져 있으면 Flutter/Dart 빌드가 알 수 없는 오류로 죽고,
# 심하면 VS Code 통합 터미널이 기동조차 못 한다(exit -65536).
# 컴파일러와 pub 가 임시 디렉터리를 많이 쓰기 때문이다.
#
# 안내 문구로 명령을 뱉지 않고 직접 고친다. 예전엔 setx 명령을 출력했는데,
# 그 안의 $env:USERPROFILE 이 cmd 창에서는 확장되지 않아 리터럴 문자열이
# 환경변수에 박히는 사고가 났다.
$sane = Join-Path $env:USERPROFILE 'AppData\Local\Temp'
foreach ($varName in @('TEMP', 'TMP')) {
    $current = [Environment]::GetEnvironmentVariable($varName, 'User')
    if ($current -and (Test-Path $current)) { continue }

    Write-Host "환경변수 $varName 이 유효하지 않습니다: '$current'" -ForegroundColor Red
    if (-not (Test-Path $sane)) { New-Item -ItemType Directory -Force $sane | Out-Null }

    [Environment]::SetEnvironmentVariable($varName, $sane, 'User')
    Set-Item -Path "Env:$varName" -Value $sane
    Write-Host "  -> $sane 로 복구했습니다 (다른 터미널은 재시작 필요)" -ForegroundColor Green
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host 'flutter 명령을 찾을 수 없습니다. Flutter SDK 설치 및 PATH를 확인하세요.' -ForegroundColor Red
    exit 1
}

Write-Host '[1/3] 의존성 설치' -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Test) {
    Write-Host '[2/3] 테스트 실행' -ForegroundColor Cyan
    flutter test
    exit $LASTEXITCODE
}

# 브라우저 자동 선택.
# Chrome 이 없는 머신에서 -d chrome 은 그냥 실패한다. 설치된 걸 고른다.
if (-not $Device) {
    Write-Host '[2/3] 브라우저 탐색' -ForegroundColor Cyan
    $devices = (flutter devices --machine | ConvertFrom-Json).id
    foreach ($candidate in @('chrome', 'edge')) {
        if ($devices -contains $candidate) { $Device = $candidate; break }
    }
    if (-not $Device) {
        Write-Host '웹 브라우저 디바이스를 찾지 못했습니다. Chrome 또는 Edge 를 설치하거나' -ForegroundColor Red
        Write-Host '-Device 로 직접 지정하세요. 사용 가능한 목록:' -ForegroundColor Yellow
        flutter devices
        exit 1
    }
    Write-Host "      -> $Device" -ForegroundColor DarkGray
}

if ($Supabase) {
    $envFile = Join-Path $PSScriptRoot 'env\dev.json'
    if (-not (Test-Path $envFile)) {
        Write-Host "env\dev.json 이 없습니다." -ForegroundColor Red
        Write-Host "env\dev.example.json 을 복사해서 값을 채우세요:" -ForegroundColor Yellow
        Write-Host "  Copy-Item env\dev.example.json env\dev.json" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "[3/3] Supabase 백엔드로 실행 (http://localhost:$Port)" -ForegroundColor Cyan
    flutter run -d $Device --web-port=$Port --dart-define-from-file=env/dev.json
}
else {
    Write-Host "[3/3] 목 데이터로 실행 (http://localhost:$Port)" -ForegroundColor Cyan
    Write-Host '      Supabase 로 붙이려면: .\run_local.ps1 -Supabase' -ForegroundColor DarkGray
    flutter run -d $Device --web-port=$Port --dart-define=FORCE_MOCK=true
}
