import 'dart:async';

/// LLM（またはモック）から届くもの。
sealed class AgentEvent {
  const AgentEvent();
}

/// 「いま何をしているか」。Loading の経過表示に使う。
final class AgentStep extends AgentEvent {
  const AgentStep(this.label, {this.progress});

  final String label;
  final double? progress;
}

/// LLM の出力の断片。A2UI の JSON ブロックと地の文が混ざって届く。
final class AgentChunk extends AgentEvent {
  const AgentChunk(this.text);

  final String text;
}

/// 途中で止めるための合図。
class CancelToken {
  bool _cancelled = false;
  final _completer = Completer<void>();

  bool get isCancelled => _cancelled;

  /// 止められたときに完了する。待ち時間の途中で抜けるのに使う。
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _completer.complete();
  }
}

/// 呼び出し先を差し替えるための窓口。モックと Gemini の 2 つの実装がある。
abstract interface class AgentBackend {
  /// 会話の履歴と新しい依頼を渡し、届いた順にイベントを流す。
  /// 失敗したらストリームのエラーとして [AgentException] を流す。
  Stream<AgentEvent> run({
    required String systemPrompt,
    required List<({String role, String text})> history,
    required String prompt,
    required CancelToken cancel,
  });
}

class AgentException implements Exception {
  const AgentException(this.kind, this.message);

  final AgentExceptionKind kind;
  final String message;

  @override
  String toString() => 'AgentException($kind): $message';
}

enum AgentExceptionKind { network, timeout }
