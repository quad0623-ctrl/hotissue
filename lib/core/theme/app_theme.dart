import 'package:flutter/material.dart';

/// 다크 우선. 실시간 순위/속보 성격의 서비스라 어두운 배경에 강조색이 튀는 편이 읽기 좋다.
///
/// 투명도가 필요한 색은 `withOpacity` 같은 버전 의존 API 대신
/// 알파를 박은 const 값으로 둔다. (Flutter 버전 간 API 변동에 영향받지 않게)
abstract final class AppColors {
  static const bg = Color(0xFF0B0B0F);
  static const surface = Color(0xFF15151C);
  static const surfaceHigh = Color(0xFF1E1E28);
  static const border = Color(0xFF2A2A36);

  static const hot = Color(0xFFFF4D4D);
  static const warm = Color(0xFFFFB020);
  static const cool = Color(0xFF4D9DFF);

  /// 순위 상승은 빨강, 하락은 파랑 (한국 증시 관습과 동일)
  static const up = Color(0xFFFF4D4D);
  static const down = Color(0xFF4D9DFF);

  static const textPrimary = Color(0xFFF2F2F5);
  static const textSecondary = Color(0xFF9A9AA8);
  static const textTertiary = Color(0xFF60606E);

  // 틴트 (알파 포함)
  static const hot12 = Color(0x1FFF4D4D);
  static const hot20 = Color(0x33FF4D4D);
  static const warm12 = Color(0x1FFFB020);
  static const cool12 = Color(0x1F4D9DFF);
  static const white08 = Color(0x14FFFFFF);
  static const black40 = Color(0x66000000);
}

/// 한글 폰트 폴백. Pretendard를 에셋으로 넣기 전까지 OS 기본 한글 폰트를 쓴다.
const kKoreanFallback = <String>[
  'Pretendard',
  'Apple SD Gothic Neo',
  'Malgun Gothic',
  'Noto Sans KR',
  'sans-serif',
];

abstract final class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.bg,
        primary: AppColors.hot,
        secondary: AppColors.warm,
        outline: AppColors.border,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
        fontFamilyFallback: kKoreanFallback,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.hot20,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: kKoreanFallback,
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontFamilyFallback: kKoreanFallback,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// 점수에 따른 강조색 (0~100)
Color heatColor(double score) {
  if (score >= 70) return AppColors.hot;
  if (score >= 45) return AppColors.warm;
  return AppColors.cool;
}

/// "3분 전" 같은 상대 시간. intl 의존성을 피하려고 직접 만든다.
String relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);

  if (diff.inSeconds < 60) return '방금';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  return '${time.month}월 ${time.day}일';
}

/// 1234 -> 1.2k
String compactCount(int n) {
  if (n < 1000) return '$n';
  final k = n / 1000;
  return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
}
