import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/ranking/ranked_issue.dart';

/// 정렬 모드 선택. "알고리즘이 마음에 안 들면 바꿔라"는 선택지를 준다.
class ModeSelector extends StatelessWidget {
  const ModeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final RankingMode selected;
  final ValueChanged<RankingMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Row(
        children: [
          for (final mode in RankingMode.values) ...[
            _Chip(
              mode: mode,
              active: mode == selected,
              onTap: () => onChanged(mode),
            ),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          Tooltip(
            message: selected.description,
            child: const Icon(
              Icons.info_outline,
              size: 15,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.mode,
    required this.active,
    required this.onTap,
  });

  final RankingMode mode;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.hot20 : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.hot : AppColors.border,
          ),
        ),
        child: Text(
          mode.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? AppColors.hot : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
