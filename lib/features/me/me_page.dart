import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/trend_source.dart';
import '../../domain/ranking/ranked_issue.dart';
import '../../state/providers.dart';

/// 익명 기반이라 프로필이랄 게 없다.
/// 대신 "이 서비스가 어떻게 순위를 매기는지"를 열어두는 화면으로 쓴다.
class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(rankingModeProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        const Text(
          '⚙️ 설정',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 16),
        const _AnonymityCard(),
        const SizedBox(height: 24),
        const _SectionTitle('정렬 기준'),
        for (final m in RankingMode.values)
          _ModeOption(
            mode: m,
            selected: m == mode,
            onTap: () {
              ref.read(rankingServiceProvider).reset();
              ref.read(rankingModeProvider.notifier).state = m;
            },
          ),
        const SizedBox(height: 12),
        _WeightTable(mode: mode),
        const SizedBox(height: 28),
        const _SectionTitle('수집 소스'),
        const SizedBox(height: 8),
        for (final s in TrendSource.visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    s.code,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.label,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Text(
                  '가중치 ${s.weight.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 28),
        const _SectionTitle('앱'),
        const SizedBox(height: 4),
        _Tile(
          icon: Icons.install_mobile,
          title: '홈 화면에 추가',
          subtitle: '설치하면 앱처럼 실행되고 알림을 받을 수 있습니다',
          onTap: () => _toast(context, 'PWA 설치 프롬프트는 Phase 4에서 연결됩니다'),
        ),
        _Tile(
          icon: Icons.notifications_none,
          title: '알림 설정',
          subtitle: '급상승 이슈, 내 글에 달린 반응',
          onTap: () => _toast(context, '알림은 Phase 4에서 연결됩니다'),
        ),
        _Tile(
          icon: Icons.gavel_outlined,
          title: '커뮤니티 이용 규칙',
          subtitle: '익명이지만 책임은 남습니다',
          onTap: () => _toast(context, '이용 규칙 문서는 Phase 5에서 작성됩니다'),
        ),
        const SizedBox(height: 24),
        Text(
          'hotissue prototype v0.1.0 · '
          '백엔드: ${ref.watch(backendSetupProvider).mode.label}',
          style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

/// 계정이 없다는 사실 자체가 이 서비스의 기능이다. 숨기지 말고 앞에 내건다.
class _AnonymityCard extends ConsumerWidget {
  const _AnonymityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(backendSetupProvider).mode;
    final ready = mode != BackendMode.mock;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.masks_outlined, size: 16, color: AppColors.warm),
              const SizedBox(width: 6),
              const Text(
                '익명으로 이용 중',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: ready ? AppColors.hot12 : AppColors.white08,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  ready ? mode.label : '오프라인 목',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: ready ? AppColors.hot : AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '가입도 로그인도 없습니다. 이메일·전화번호·프로필을 저장하지 않습니다.\n'
            '닉네임은 방마다 새로 만들어지므로 방을 넘나드는 추적이 불가능합니다.',
            style: TextStyle(
              fontSize: 11,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '대신 도배 차단과 1인 1추천을 위해 익명 세션 식별자 하나만 유지합니다.\n'
            '브라우저 데이터를 지우면 그 식별자도 사라집니다.',
            style: TextStyle(
              fontSize: 11,
              height: 1.6,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 정렬 모드 선택지.
///
/// RadioListTile 을 쓰지 않는 이유: Flutter 3.32 에서 groupValue/onChanged 가
/// RadioGroup 으로 대체되며 deprecated 됐다. 버전 의존을 만들 이유가 없고,
/// 어차피 앱 전체가 커스텀 스타일이라 직접 그리는 편이 일관적이다.
class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final RankingMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? AppColors.hot : AppColors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mode.description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeightTable extends StatelessWidget {
  const _WeightTable({required this.mode});

  final RankingMode mode;

  @override
  Widget build(BuildContext context) {
    final w = mode.weights;
    final rows = <(String, String)>[
      ('순위 반영', w.source.toStringAsFixed(2)),
      ('상승세 반영', w.velocity.toStringAsFixed(2)),
      ('확산도 반영', w.diversity.toStringAsFixed(2)),
      ('참여도 반영', w.engagement.toStringAsFixed(2)),
      ('반감기', '${w.halfLife.inMinutes}분'),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppColors.textSecondary,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, size: 20, color: AppColors.textSecondary),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        size: 18,
        color: AppColors.textTertiary,
      ),
      onTap: onTap,
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        duration: const Duration(seconds: 2),
      ),
    );
}
