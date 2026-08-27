/// 빌드 타임 설정. `--dart-define` 또는 `--dart-define-from-file` 로 주입한다.
abstract final class AppConfig {
  // ── Supabase (선택) ────────────────────────────────────────────
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  // Supabase 가 "anon key" 를 "publishable key" 로 이름을 바꿨다.
  // 새 이름을 우선하되 기존 키 이름도 계속 받는다.
  static const _publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const _legacyAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get supabaseKey =>
      _publishableKey.isNotEmpty ? _publishableKey : _legacyAnonKey;

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  // ── 로컬 수집기 ────────────────────────────────────────────────
  /// 예: `http://localhost:8787`. 실데이터를 쓰는 가장 빠른 경로다.
  static const collectorUrl = String.fromEnvironment('COLLECTOR_URL');

  static bool get hasCollector => collectorUrl.isNotEmpty;

  // ── 강제 목 ───────────────────────────────────────────────────
  /// 설정이 있어도 목으로 뜬다. UI 작업할 때 유용하다.
  static const forceMockBackend = bool.fromEnvironment('FORCE_MOCK');

  /// 어느 백엔드로 뜰지 결정한다.
  ///
  /// 우선순위: 목 강제 > Supabase > 수집기 > 목 폴백.
  /// Supabase 를 먼저 두는 이유는 그게 배포 대상 백엔드이기 때문이다.
  /// 수집기는 로컬 개발과 실데이터 확인용이다.
  static BackendMode get preferredMode {
    if (forceMockBackend) return BackendMode.mock;
    if (hasSupabase) return BackendMode.supabase;
    if (hasCollector) return BackendMode.collector;
    return BackendMode.mock;
  }
}

enum BackendMode {
  supabase('Supabase'),
  collector('실시간 수집기'),
  mock('목 데이터');

  const BackendMode(this.label);
  final String label;
}
