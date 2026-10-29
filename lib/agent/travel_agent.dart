import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';

import '../catalog/travel_catalog.dart';
import '../state/ai_ui_state.dart';
import 'backend.dart';

const _suggestedPrompts = [
  '週末、箱根で温泉旅行を計画して',
  '雨の日でも楽しめる場所は？',
  '予算 3 万円で 1 泊したい',
];

/// GenUI の `Conversation` と呼び出し先をつなぎ、結果を [AiUiState] に写す。
///
/// - 送信してから最初の断片が届くまで → Loading（経過のステップつき）
/// - 断片が届きはじめてから終わるまで → Partial（画面が育っていく）
/// - 最後まで届いて画面が組めた → Ideal
/// - 途中で失敗した・中身が使えない → Failed（途中までは残す）
/// - ユーザーが止めた → 止めた時点の Partial
class TravelAgent extends ChangeNotifier {
  TravelAgent({required this.backend}) {
    _reset();
  }

  /// 呼び出し先。モックと Gemini を途中で差し替えられる。
  AgentBackend backend;

  final Catalog catalog = buildTravelCatalog();
  late SurfaceController _surfaces;
  late A2uiTransportAdapter _transport;
  late Conversation _conversation;
  StreamSubscription<ConversationEvent>? _events;

  AiUiState _state = const AiEmpty(suggestedPrompts: _suggestedPrompts);
  AiUiState get state => _state;

  /// 直近の依頼。再生成と「編集して再送」に使う。
  String lastPrompt = '';

  SurfaceController get surfaces => _surfaces;

  final List<({String role, String text})> _history = [];
  final List<String> _steps = [];
  double? _progress;
  String _text = '';
  final List<String> _surfaceIds = [];
  bool _receiving = false;
  CancelToken? _cancel;
  AgentException? _error;
  final Stopwatch _clock = Stopwatch();
  Timer? _ticker;

  late final String _systemPrompt = PromptBuilder.chat(
    catalog: catalog,
    systemPromptFragments: [
      'あなたは旅の相談にのるアシスタントです。日本語で答えてください。',
      '最初に 1〜2 文で返事をしてから、UI を組み立ててください。',
      '予約や決済はできません。頼まれたら、できないと伝えてください。',
    ],
  ).systemPromptJoined();

  void _reset() {
    _events?.cancel();
    _surfaces = SurfaceController(catalogs: [catalog]);
    _transport = A2uiTransportAdapter(onSend: _onSend);
    _conversation = Conversation(controller: _surfaces, transport: _transport);
    _events = _conversation.events.listen(_onConversationEvent);
  }

  void _onConversationEvent(ConversationEvent event) {
    switch (event) {
      case ConversationContentReceived(:final text):
        _text += text;
      case ConversationSurfaceAdded(:final surfaceId):
        if (!_surfaceIds.contains(surfaceId)) _surfaceIds.add(surfaceId);
      case ConversationComponentsUpdated():
        break;
      case ConversationSurfaceRemoved(:final surfaceId):
        _surfaceIds.remove(surfaceId);
      case ConversationWaiting():
      case ConversationError():
        return;
    }
    _emitReceiving();
  }

  /// 送信する。Empty・Ideal・Failed・止めた Partial から呼べる。
  Future<void> send(String prompt) async {
    final p = prompt.trim();
    if (p.isEmpty || isBusy) return;
    lastPrompt = p;
    _surfaces.dispose();
    _transport.dispose();
    _conversation.dispose();
    _reset();
    _steps.clear();
    _progress = null;
    _text = '';
    _surfaceIds.clear();
    _receiving = false;
    _error = null;
    _cancel = CancelToken();
    _clock
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _receiving ? _emitReceiving() : _emitLoading();
    });
    _emitLoading();

    await _conversation.sendRequest(ChatMessage.user(p));
    _finish();
  }

  Future<void> regenerate() => send(lastPrompt);

  bool get isBusy => switch (_state) {
    AiLoading() => true,
    AiPartial(:final stoppedByUser) => !stoppedByUser,
    _ => false,
  };

  /// 止める。届いた分は Partial として残す。
  void stop() {
    if (!isBusy) return;
    _cancel?.cancel();
  }

  Future<void> _onSend(ChatMessage message) async {
    final cancel = _cancel!;
    try {
      await for (final event in backend.run(
        systemPrompt: _systemPrompt,
        history: List.of(_history),
        prompt: lastPrompt,
        cancel: cancel,
      )) {
        if (cancel.isCancelled) break;
        switch (event) {
          case AgentStep(:final label, :final progress):
            _steps.add(label);
            _progress = progress;
            if (!_receiving) _emitLoading();
          case AgentChunk(:final text):
            _receiving = true;
            _transport.addChunk(text);
            // 解析が追いつくのを待ってから描き直す
            await Future<void>.delayed(Duration.zero);
            _emitReceiving();
        }
      }
    } on AgentException catch (e) {
      _error = e;
    }
  }

  void _finish() {
    _ticker?.cancel();
    _clock.stop();
    final elapsed = _clock.elapsed;
    final cancelled = _cancel?.isCancelled ?? false;

    if (_error case final e?) {
      _set(
        AiFailed(
          kind: e.kind == AgentExceptionKind.timeout
              ? AiFailureKind.timeout
              : AiFailureKind.network,
          message: e.message,
          partialText: _text,
          surfaceIds: List.of(_surfaceIds),
        ),
      );
      return;
    }
    if (cancelled) {
      if (!_receiving) {
        // まだ何も届いていなければ、入力し直せる Empty に戻す
        _set(const AiEmpty(suggestedPrompts: _suggestedPrompts));
      } else {
        _set(
          AiPartial(
            textSoFar: _text,
            surfaceIds: List.of(_surfaceIds),
            elapsed: elapsed,
            isCancellable: false,
            stoppedByUser: true,
          ),
        );
      }
      return;
    }
    _history
      ..add((role: 'user', text: lastPrompt))
      ..add((role: 'model', text: _text));
    // 返ってきたが画面が組めなかった＝気づきにくい失敗として扱う
    if (_surfaceIds.isEmpty) {
      _set(
        AiFailed(
          kind: AiFailureKind.lowQuality,
          message: 'プランを組み立てられませんでした',
          partialText: _text,
          surfaceIds: const [],
        ),
      );
      return;
    }
    _set(
      AiIdeal(text: _text, surfaceIds: List.of(_surfaceIds), elapsed: elapsed),
    );
  }

  void _emitLoading() => _set(
    AiLoading(
      steps: List.of(_steps),
      elapsed: _clock.elapsed,
      progress: _progress,
      isCancellable: true,
    ),
  );

  void _emitReceiving() {
    if (!_receiving || _cancel == null || _clock.isRunning == false) return;
    _set(
      AiPartial(
        textSoFar: _text,
        surfaceIds: List.of(_surfaceIds),
        elapsed: _clock.elapsed,
        isCancellable: true,
      ),
    );
  }

  void _set(AiUiState s) {
    _state = s;
    notifyListeners();
  }

  /// 最初の画面に戻す。
  void clear() {
    if (isBusy) return;
    _set(const AiEmpty(suggestedPrompts: _suggestedPrompts));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _events?.cancel();
    _conversation.dispose();
    _transport.dispose();
    _surfaces.dispose();
    super.dispose();
  }
}
