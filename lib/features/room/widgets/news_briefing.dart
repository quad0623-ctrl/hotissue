import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/issue.dart';

/// 방 상단 뉴스 브리핑.
///
/// **왜 필요한가**: 방에 들어와도 헤드라인만 보이고 무슨 일인지 알 수 없었다.
/// 사람들이 내용을 모른 채 대화하는 셈이었다.
///
/// **무엇을 보여주는가**: 언론사 RSS 가 피드에 담아 배포하는 기사 리드다.
/// 기사 본문을 가져오지 않는다. 리드는 자르되 문장을 바꾸지 않는다.
///
/// **지켜야 할 것**: 인용마다 언론사명과 원문 링크가 반드시 함께 붙는다.
class NewsBriefing extends StatelessWidget {
  const NewsBriefing({super.key, required this.articles});

  final List<Article> articles;

  @override
  Widget build(BuildContext context) {
    if (articles.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.article_outlined, size: 14, color: AppColors.cool),
            const SizedBox(width: 5),
            const Text(
              '뉴스 브리핑',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 6),
            Text(
              '${articles.length}건',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final article in articles)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ArticleCard(article: article),
          ),
        const Text(
          '각 언론사가 RSS로 제공한 기사 요약입니다. 전문은 원문에서 확인하세요.',
          style: TextStyle(
            fontSize: 10,
            height: 1.5,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _ArticleCard extends StatefulWidget {
  const _ArticleCard({required this.article});

  final Article article;

  @override
  State<_ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends State<_ArticleCard> {
  bool _expanded = false;

  Future<void> _openOriginal() async {
    final raw = widget.article.url;
    if (raw == null || raw.isEmpty) return;

    final uri = Uri.tryParse(raw);
    if (uri == null) return;

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('원문을 열지 못했습니다', style: TextStyle(fontSize: 13)),
            duration: Duration(seconds: 2),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final hasUrl = article.url != null && article.url!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 언론사명은 생략할 수 없다. 인용의 최소 조건이다.
              Flexible(
                child: Text(
                  article.outletLabel ?? '출처 미상',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.cool,
                  ),
                ),
              ),
              if (article.publishedAt != null) ...[
                const SizedBox(width: 6),
                Text(
                  relativeTime(article.publishedAt!),
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          Text(
            article.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (article.hasSummary) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: Text(
                article.summary!,
                // 자르되 문장을 바꾸지 않는다. 더 보려면 펼친다.
                maxLines: _expanded ? null : 3,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.55,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
          if (hasUrl) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _openOriginal,
              behavior: HitTestBehavior.opaque,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '원문 보기',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.cool,
                    ),
                  ),
                  SizedBox(width: 3),
                  Icon(Icons.north_east, size: 11, color: AppColors.cool),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
