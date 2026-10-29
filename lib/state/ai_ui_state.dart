/// スライド「sealed class で 5 状態をモデリング」と同じ形の状態。
///
/// GenUI の `Conversation` のイベントを、この 5 つ（＋失敗）に写して画面を作る。
sealed class AiUiState {
  const AiUiState();
}

/// Empty — 何を入力すればいいか分からないユーザーを導く。
final class AiEmpty extends AiUiState {
  const AiEmpty({required this.suggestedPrompts});

  final List<String> suggestedPrompts;
}

/// Loading — 「今なにをしているか」を持たせるのが肝。
final class AiLoading extends AiUiState {
  const AiLoading({
    required this.steps,
    required this.elapsed,
    this.progress,
    required this.isCancellable,
  });

  /// これまでに通ったステップ。最後の 1 つが「いまやっていること」。
  final List<String> steps;
  final Duration elapsed;

  /// 分かるときだけ 0.0〜1.0。分からなければ null（不確定のインジケーター）。
  final double? progress;
  final bool isCancellable;

  String get stepLabel => steps.isEmpty ? '' : steps.last;
}

/// Partial — 最も長く表示される状態。生成途中の出力が育っていく。
final class AiPartial extends AiUiState {
  const AiPartial({
    required this.textSoFar,
    required this.surfaceIds,
    required this.elapsed,
    required this.isCancellable,
    this.stoppedByUser = false,
  });

  final String textSoFar;
  final List<String> surfaceIds;
  final Duration elapsed;
  final bool isCancellable;

  /// ユーザーが止めた。失敗ではなく「途中で終わった Partial」として残す。
  final bool stoppedByUser;
}

/// Ideal — 意図通りに、価値のある中身が表示できている。
final class AiIdeal extends AiUiState {
  const AiIdeal({
    required this.text,
    required this.surfaceIds,
    required this.elapsed,
  });

  final String text;
  final List<String> surfaceIds;
  final Duration elapsed;
}

/// 失敗の種類。従来のエラーに加えて「気づきにくい失敗」を含む。
enum AiFailureKind {
  /// 通信が切れた・つながらない。
  network,

  /// 待ちすぎた。
  timeout,

  /// 返ってきたが、中身が使えない（画面が組めない・短すぎる）。
  lowQuality,
}

/// Error — 失敗しても、途中までの出力は残して回復の導線を出す。
final class AiFailed extends AiUiState {
  const AiFailed({
    required this.kind,
    required this.message,
    required this.partialText,
    required this.surfaceIds,
  });

  final AiFailureKind kind;
  final String message;
  final String partialText;
  final List<String> surfaceIds;
}
