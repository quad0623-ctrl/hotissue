import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 글자 수 카운터를 숨긴다. maxLength 는 유지해서 입력 자체는 막되,
/// "480/500" 같은 표시가 채팅 입력창 아래에 뜨는 건 방해가 된다.
Widget? _noCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) =>
    null;

/// 하단 입력창. 텍스트 + 이미지 첨부.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.onSend,
    required this.onAttachImage,
  });

  final ValueChanged<String> onSend;
  final VoidCallback onAttachImage;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final next = _controller.text.trim().isNotEmpty;
      if (next != _canSend) setState(() => _canSend = next);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      // 키보드 여백은 Scaffold(resizeToAvoidBottomInset)가 처리하고,
      // 홈 인디케이터 여백은 아래 SafeArea가 처리한다.
      padding: const EdgeInsets.all(8),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 21),
              color: AppColors.textSecondary,
              tooltip: '이미지 첨부',
              onPressed: widget.onAttachImage,
            ),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 110),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 500,
                  buildCounter: _noCounter,
                  style: const TextStyle(fontSize: 14),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '이 이슈에 대해 이야기해보세요',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceHigh,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 19),
              color: _canSend ? Colors.white : AppColors.textTertiary,
              style: IconButton.styleFrom(
                backgroundColor:
                    _canSend ? AppColors.hot : AppColors.surfaceHigh,
                minimumSize: const Size(36, 36),
              ),
              onPressed: _canSend ? _send : null,
            ),
          ],
        ),
      ),
    );
  }
}
