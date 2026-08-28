import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../state/providers.dart';

/// 순위 화면 헤더.
///
/// 데이터는 5분에 한 번만 바뀐다. 그 사이 화면이 살아있다는 걸 보여주는
/// 유일하게 정직한 값이 **마지막 갱신 이후 흐른 시간**이다. 이건 매초 바뀐다.
///
/// 여기서만 [dataFreshnessProvider] 를 구독한다. 순위 리스트가 구독하면
/// 데이터가 안 바뀌어도 매초 리빌드된다.
class LiveHeader extends ConsumerWidget {
  const LiveHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final freshness = ref.watch(dataFreshnessProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🔥 지금 한국은',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            '검색어를 그대로 베끼지 않고 다시 줄 세웁니다',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 10),
          _FreshnessBar(freshness: freshness),
        ],
      ),
    );
  }
}

class _FreshnessBar extends StatelessWidget {
  const _FreshnessBar({required this.freshness});

  final DataFreshness freshness;

  @override
  Widget build(BuildContext context) {
    final stale = freshness.state == FreshnessState.stale;
    final tone = stale ? AppColors.textTertiary : AppColors.textSecondary;

    return Row(
      children: [
        _LiveDot(state: freshness.state),
        const SizedBox(width: 8),
        Text(
          freshness.ageLabel,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: stale ? AppColors.warm : tone,
            // 숫자가 매초 바뀌므로 폭이 흔들리지 않게 고정폭 숫자를 쓴다
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (freshness.nextLabel != null) ...[
          const SizedBox(width: 8),
          Container(width: 1, height: 9, color: AppColors.border),
          const SizedBox(width: 8),
          Text(
            freshness.nextLabel!,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textTertiary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

/// 데이터 상태를 그대로 반영하는 도트.
///
/// 예전에는 1.1초 주기로 무조건 깜빡였다. 수집이 멈춰도 똑같이 깜빡여서
/// **거짓 신호**였다. 이제 갱신 직후에만 강하게 퍼지고, 끊기면 죽는다.
class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.state});

  final FreshnessState state;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with TickerProviderStateMixin {
  /// 평상시 느린 호흡
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  /// 갱신 순간 한 번 퍼지는 링
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(_LiveDot old) {
    super.didUpdateWidget(old);

    // 대기 → 방금갱신 으로 넘어온 순간에만 링을 쏜다
    if (widget.state == FreshnessState.justUpdated &&
        old.state != FreshnessState.justUpdated) {
      _ripple.forward(from: 0);
    }

    if (widget.state == FreshnessState.stale) {
      _breath.stop();
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _ripple.dispose();
    super.dispose();
  }

  Color get _color => switch (widget.state) {
        FreshnessState.stale => AppColors.textTertiary,
        FreshnessState.unknown => AppColors.textTertiary,
        _ => AppColors.hot,
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 갱신 순간 퍼지는 링
          AnimatedBuilder(
            animation: _ripple,
            builder: (_, __) {
              if (_ripple.isDismissed) return const SizedBox.shrink();
              final t = _ripple.value;
              return Opacity(
                opacity: (1 - t) * 0.55,
                child: Container(
                  width: 8 + t * 8,
                  height: 8 + t * 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.hot, width: 1.2),
                  ),
                ),
              );
            },
          ),
          // 도트 본체
          AnimatedBuilder(
            animation: _breath,
            builder: (_, child) {
              final dim = widget.state == FreshnessState.stale;
              return Opacity(
                opacity: dim ? 0.4 : 0.55 + _breath.value * 0.45,
                child: child,
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}
