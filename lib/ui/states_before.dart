import 'package:flutter/material.dart';

import '../state/ai_ui_state.dart';
import 'widgets.dart';

/// before：とりあえず作った画面。
///
/// - Empty：何も出さない
/// - Loading / Partial：全画面スピナー。止められない。途中経過も見せない
/// - Error：エラーコードだけ。途中まで届いていた中身は捨てる
/// - 中身のない返事も、そのまま成功として出してしまう
class BeforeView extends StatelessWidget {
  const BeforeView({
    super.key,
    required this.state,
    required this.prompt,
    required this.surfaces,
    required this.onDismissError,
  });

  final AiUiState state;
  final String prompt;
  final List<Widget> Function(List<String> ids) surfaces;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      AiEmpty() => const SizedBox.expand(),
      AiLoading() || AiPartial(stoppedByUser: false) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('読み込み中…'),
          ],
        ),
      ),
      AiPartial(:final textSoFar, :final surfaceIds) ||
      AiIdeal(text: final textSoFar, :final surfaceIds) => ConversationList(
        children: [
          UserBubble(prompt),
          if (textSoFar.isNotEmpty) Text(textSoFar),
          ...surfaces(surfaceIds),
        ],
      ),
      AiFailed(kind: AiFailureKind.lowQuality, :final partialText) =>
        ConversationList(children: [UserBubble(prompt), Text(partialText)]),
      AiFailed(:final kind) => Center(
        child: AlertDialog(
          title: const Text('エラーが発生しました'),
          content: Text('(E_${kind.name.toUpperCase()})'),
          actions: [
            TextButton(onPressed: onDismissError, child: const Text('OK')),
          ],
        ),
      ),
    };
  }
}
