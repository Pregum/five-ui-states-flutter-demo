import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

import '../agent/backend.dart';
import '../agent/gemini_backend.dart';
import '../agent/mock_backend.dart';
import '../agent/travel_agent.dart';
import 'states_after.dart';
import 'states_before.dart';

const _geminiKey = String.fromEnvironment('GEMINI_API_KEY');

/// 画面の作り方。before（とりあえず作った版）と after（5 状態で設計した版）。
enum DesignMode { before, after }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DesignMode _mode = DesignMode.after;
  MockScenario _scenario = MockScenario.success;
  bool _live = false;
  late final TravelAgent _agent = TravelAgent(backend: _buildBackend());
  final _input = TextEditingController();

  AgentBackend _buildBackend() => _live && _geminiKey.isNotEmpty
      ? GeminiBackend(apiKey: _geminiKey)
      : MockBackend(scenario: _scenario);

  void _rebuildBackend() => _agent.backend = _buildBackend();

  /// 撮影用：`?mode=before&scenario=networkError&send=1` のように URL で状態を決める。
  @override
  void initState() {
    super.initState();
    final q = Uri.base.queryParameters;
    if (q['mode'] == 'before') _mode = DesignMode.before;
    final scenario = MockScenario.values.where((s) => s.name == q['scenario']);
    if (scenario.isNotEmpty) {
      _scenario = scenario.first;
      _rebuildBackend();
    }
    if (q['send'] == '1') {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _send('週末、箱根で温泉旅行を計画して'),
      );
      if (q['stopAfter'] case final ms?) {
        Future<void>.delayed(
          Duration(milliseconds: int.parse(ms)),
          _agent.stop,
        );
      }
    }
  }

  void _send([String? text]) {
    final t = text ?? _input.text;
    _input.clear();
    _agent.send(t);
  }

  void _editAndResend() {
    _input.text = _agent.lastPrompt;
    _agent.clear();
  }

  @override
  void dispose() {
    _agent.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('✦ AI に旅の相談'),
        actions: [
          SegmentedButton<DesignMode>(
            segments: const [
              ButtonSegment(value: DesignMode.before, label: Text('before')),
              ButtonSegment(value: DesignMode.after, label: Text('after')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          PopupMenuButton<Object>(
            tooltip: '応答の取り方',
            icon: const Icon(Icons.tune),
            onSelected: (v) => setState(() {
              if (v is MockScenario) {
                _scenario = v;
                _live = false;
              } else {
                _live = true;
              }
              _rebuildBackend();
            }),
            itemBuilder: (_) => [
              for (final s in MockScenario.values)
                CheckedPopupMenuItem(
                  value: s,
                  checked: !_live && _scenario == s,
                  child: Text('モック：${s.label}'),
                ),
              CheckedPopupMenuItem(
                value: 'live',
                enabled: _geminiKey.isNotEmpty,
                checked: _live,
                child: Text(
                  _geminiKey.isEmpty ? 'Gemini（API キー未設定）' : 'Gemini に本当に送る',
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: _agent,
        builder: (context, _) {
          final state = _agent.state;
          List<Widget> surface(List<String> ids) => [
            for (final id in ids)
              Surface(surfaceContext: _agent.surfaces.contextFor(id)),
          ];
          return Column(
            children: [
              Expanded(
                child: switch (_mode) {
                  DesignMode.before => BeforeView(
                    state: state,
                    prompt: _agent.lastPrompt,
                    surfaces: surface,
                    onDismissError: _agent.clear,
                  ),
                  DesignMode.after => AfterView(
                    state: state,
                    prompt: _agent.lastPrompt,
                    surfaces: surface,
                    onSuggestion: _send,
                    onRegenerate: _agent.regenerate,
                    onEdit: _editAndResend,
                  ),
                },
              ),
              _InputBar(
                controller: _input,
                showStop: _mode == DesignMode.after && _agent.isBusy,
                enabled: !_agent.isBusy,
                onSend: _send,
                onStop: _agent.stop,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.showStop,
    required this.enabled,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool showStop;
  final bool enabled;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                onSubmitted: onSend,
                decoration: InputDecoration(
                  hintText: enabled ? 'メッセージを入力' : '生成中…',
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (showStop)
              FilledButton.icon(
                onPressed: onStop,
                style: FilledButton.styleFrom(backgroundColor: scheme.error),
                icon: const Icon(Icons.stop),
                label: const Text('停止'),
              )
            else
              FilledButton(
                onPressed: enabled ? () => onSend(controller.text) : null,
                child: const Text('送信'),
              ),
          ],
        ),
      ),
    );
  }
}
