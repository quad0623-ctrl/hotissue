import 'dart:io';

/// 최소한의 `.env` 로더.
///
/// 패키지를 하나 더 들이지 않는다. 필요한 건 `KEY=value` 몇 줄이 전부다.
/// **이미 프로세스 환경변수에 있는 값은 덮어쓰지 않는다** — 배포 환경에서
/// 주입한 값이 저장소의 파일에 밀리면 안 되기 때문이다.
Map<String, String> loadDotEnv([String path = '.env']) {
  final merged = Map<String, String>.from(Platform.environment);

  final file = File(path);
  if (!file.existsSync()) return merged;

  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final eq = line.indexOf('=');
    if (eq <= 0) continue;

    final key = line.substring(0, eq).trim();
    if (merged.containsKey(key)) continue; // 프로세스 환경변수가 우선

    var value = line.substring(eq + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    merged[key] = value;
  }

  return merged;
}
