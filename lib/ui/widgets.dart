import 'package:flutter/material.dart';

/// ユーザーの依頼（右寄せの吹き出し）。
class UserBubble extends StatelessWidget {
  const UserBubble(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text),
      ),
    );
  }
}

/// 中身がまだ無いところに置く骨組み。ゆっくり明滅させて「待っている」と伝える。
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 64});

  final double height;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 0.8).animate(_c),
      child: Container(
        height: widget.height,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

String formatElapsed(Duration d) => '${d.inSeconds} 秒';

/// 撮影用：`?scroll=end` なら、中身が増えるたびに一番下まで送る。
final bool _scrollToEnd = Uri.base.queryParameters['scroll'] == 'end';

/// 会話の縦スクロール。撮影時だけ末尾に追従する。
class ConversationList extends StatefulWidget {
  const ConversationList({super.key, required this.children});

  final List<Widget> children;

  @override
  State<ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<ConversationList> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_scrollToEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) {
          _controller.jumpTo(_controller.position.maxScrollExtent);
        }
      });
    }
    return ListView(
      controller: _controller,
      padding: const EdgeInsets.all(16),
      children: widget.children,
    );
  }
}
