import 'package:flutter/material.dart';

import '../../../domain/ranking/ranked_issue.dart';

/// 순위가 바뀌면 카드가 자리를 옮기는 리스트.
///
/// **왜 필요한가**: 수집기가 5분마다 순위를 갱신하고 실제로 순서가 바뀌는데,
/// 그냥 리스트를 교체하면 화면이 순간적으로 뒤바뀔 뿐 "움직였다"는 인상이 남지 않는다.
/// 5분에 한 번뿐인 변화라서 더더욱 놓치면 안 된다.
///
/// **왜 Stack 인가**: `ListView` 는 순서가 바뀌면 그냥 다시 그린다.
/// 자리 이동을 애니메이션하려면 각 카드의 위치를 직접 잡아야 한다.
/// 패키지를 새로 들이는 대신 `AnimatedPositioned` 로 해결한다.
///
/// **자식 순서는 고정한다** (이슈 id 정렬). 순위 순서대로 넣으면 리빌드마다
/// z-order 가 바뀌어 애니메이션 도중 카드가 서로를 덮는다.
/// 위치만 `top` 으로 옮기고 그리는 순서는 건드리지 않는다.
class AnimatedRankList extends StatelessWidget {
  const AnimatedRankList({
    super.key,
    required this.items,
    required this.itemHeight,
    required this.itemBuilder,
  });

  final List<RankedIssue> items;

  /// 모든 카드가 같은 높이여야 위치 계산이 성립한다.
  final double itemHeight;

  final Widget Function(BuildContext context, RankedIssue item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    // 순위 → 화면상의 y 위치
    final topOf = <String, int>{
      for (var i = 0; i < items.length; i++) items[i].issue.id: i,
    };

    // 그리는 순서는 id 로 고정한다 (z-order 안정화)
    final stable = [...items]..sort((a, b) => a.issue.id.compareTo(b.issue.id));

    return SizedBox(
      height: items.length * itemHeight,
      child: Stack(
        children: [
          for (final item in stable)
            AnimatedPositioned(
              key: ValueKey(item.issue.id),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              top: (topOf[item.issue.id] ?? 0) * itemHeight,
              left: 0,
              right: 0,
              height: itemHeight,
              child: _EnterFade(
                // 새 이슈만 페이드인. 이미 있던 카드는 즉시 보인다.
                key: ValueKey('fade_${item.issue.id}'),
                child: itemBuilder(context, item),
              ),
            ),
        ],
      ),
    );
  }
}

/// 처음 붙을 때만 아래에서 떠오르며 나타난다.
///
/// 사라지는 애니메이션은 없다. 그러려면 지워진 항목을 붙들고 있어야 하는데,
/// 순위표에서 빠진 이슈를 계속 그리는 건 화면이 거짓말하는 쪽에 가깝다.
class _EnterFade extends StatefulWidget {
  const _EnterFade({super.key, required this.child});

  final Widget child;

  @override
  State<_EnterFade> createState() => _EnterFadeState();
}

class _EnterFadeState extends State<_EnterFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }
}
