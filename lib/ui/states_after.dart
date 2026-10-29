import 'package:flutter/material.dart';

import '../state/ai_ui_state.dart';
import 'widgets.dart';

/// after：5 状態で設計した画面。状態ごとの switch がそのまま画面の設計図になる。
class AfterView extends StatelessWidget {
  const AfterView({
    super.key,
    required this.state,
    required this.prompt,
    required this.surfaces,
    required this.onSuggestion,
    required this.onRegenerate,
    required this.onEdit,
  });

  final AiUiState state;
  final String prompt;
  final List<Widget> Function(List<String> ids) surfaces;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onRegenerate;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      AiEmpty(:final suggestedPrompts) => _EmptyView(
        suggestions: suggestedPrompts,
        onTap: onSuggestion,
      ),
      AiLoading(:final steps, :final elapsed, :final progress) => _Scroll([
        UserBubble(prompt),
        _StepList(steps: steps, elapsed: elapsed, progress: progress),
        const SizedBox(height: 12),
        const Skeleton(height: 28),
        const Skeleton(),
        const Skeleton(),
      ]),
      AiPartial(
        :final textSoFar,
        :final surfaceIds,
        :final elapsed,
        :final stoppedByUser,
      ) =>
        _Scroll([
          UserBubble(prompt),
          if (textSoFar.isNotEmpty) Text(textSoFar),
          ...surfaces(surfaceIds),
          if (stoppedByUser)
            _Banner(
              color: Theme.of(context).colorScheme.outline,
              message: '途中で止めました。ここまでの内容は残っています',
              actions: [
                (Icons.refresh, 'もう一度生成', onRegenerate),
                (Icons.edit_outlined, '編集して再送', onEdit),
              ],
            )
          else ...[
            const Skeleton(height: 48),
            _Generating(elapsed: elapsed),
          ],
        ]),
      AiIdeal(:final text, :final surfaceIds, :final elapsed) => _Scroll([
        UserBubble(prompt),
        if (text.isNotEmpty) Text(text),
        ...surfaces(surfaceIds),
        const SizedBox(height: 8),
        _IdealActions(
          elapsed: elapsed,
          onRegenerate: onRegenerate,
          onEdit: onEdit,
        ),
      ]),
      AiFailed(
        :final kind,
        :final message,
        :final partialText,
        :final surfaceIds,
      ) =>
        _Scroll([
          UserBubble(prompt),
          if (partialText.isNotEmpty)
            Opacity(opacity: 0.6, child: Text(partialText)),
          ...surfaces(surfaceIds),
          _Banner(
            color: Theme.of(context).colorScheme.error,
            message: switch (kind) {
              AiFailureKind.network => '通信が途切れました。ここまでの内容は残っています',
              AiFailureKind.timeout => '時間がかかりすぎたため中断しました',
              AiFailureKind.lowQuality => '$message。日程や予算を足すと作りやすくなります',
            },
            actions: [
              (Icons.refresh, 'もう一度生成', onRegenerate),
              (Icons.edit_outlined, '編集して再送', onEdit),
            ],
          ),
        ]),
    };
  }
}

class _Scroll extends StatelessWidget {
  const _Scroll(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ConversationList(children: children);
}

/// Empty：できること・頼み方の例・できないこと。
class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.suggestions, required this.onTap});

  final List<String> suggestions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('旅の相談ができます', style: t.titleLarge),
        const SizedBox(height: 4),
        Text('宿探し・旅程づくり・持ち物リストなど', style: t.bodyMedium),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in suggestions)
              ActionChip(label: Text(s), onPressed: () => onTap(s)),
          ],
        ),
        const SizedBox(height: 16),
        Text('※ 予約・決済はできません', style: t.bodySmall),
      ],
    );
  }
}

/// Loading：いま何をしているか・経過時間・進み具合。
class _StepList extends StatelessWidget {
  const _StepList({
    required this.steps,
    required this.elapsed,
    required this.progress,
  });

  final List<String> steps;
  final Duration elapsed;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: i == steps.length - 1
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Icon(Icons.check, size: 18, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(steps[i])),
                if (i == 0)
                  Text(
                    formatElapsed(elapsed),
                    style: TextStyle(color: scheme.outline),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        // 進み具合が分かるときだけ確定、分からなければ不確定のバー
        LinearProgressIndicator(value: progress),
      ],
    );
  }
}

class _Generating extends StatelessWidget {
  const _Generating({required this.elapsed});

  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            '生成中（${formatElapsed(elapsed)}）',
            style: TextStyle(color: color),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.message,
    required this.actions,
  });

  final Color color;
  final String message;
  final List<(IconData, String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final (icon, label, onPressed) in actions)
                OutlinedButton.icon(
                  onPressed: onPressed,
                  icon: Icon(icon, size: 18),
                  label: Text(label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ideal：やり直し・修正・良し悪しを伝える。
class _IdealActions extends StatelessWidget {
  const _IdealActions({
    required this.elapsed,
    required this.onRegenerate,
    required this.onEdit,
  });

  final Duration elapsed;
  final VoidCallback onRegenerate;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    void thanks(String s) =>
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('「$s」を送りました。今後の提案に使います')));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: onRegenerate,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('再生成'),
        ),
        OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('編集'),
        ),
        IconButton(
          onPressed: () => thanks('良い'),
          icon: const Icon(Icons.thumb_up_outlined),
        ),
        IconButton(
          onPressed: () => thanks('違う'),
          icon: const Icon(Icons.thumb_down_outlined),
        ),
        Text(
          formatElapsed(elapsed),
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      ],
    );
  }
}
