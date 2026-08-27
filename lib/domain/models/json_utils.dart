/// Supabase 행(Map<String, dynamic>) 파싱 헬퍼.
///
/// 값이 깨졌다고 화면 전체가 죽으면 안 되므로, 모든 헬퍼는 예외 대신
/// 안전한 기본값을 돌려준다. 수집기가 새 필드를 추가하거나 잠시 null을 보내도
/// 구버전 클라이언트가 버틴다.
library;

/// Postgres timestamptz → 로컬 DateTime.
DateTime parseTime(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toLocal();
  }
  return DateTime.now();
}

int parseInt(Object? value) => (value as num?)?.toInt() ?? 0;

List<String> parseStringList(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];
