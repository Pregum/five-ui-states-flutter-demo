import 'package:five_state_demo/agent/mock_backend.dart';
import 'package:five_state_demo/agent/travel_agent.dart';
import 'package:five_state_demo/state/ai_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// スライド A-8「状態設計のテスト」と同じことを、デモアプリで確かめる。
void main() {
  Future<List<AiUiState>> run(MockScenario scenario, {int? stopAfterMs}) async {
    final agent = TravelAgent(
      backend: MockBackend(scenario: scenario, speed: 40),
    );
    final states = <AiUiState>[];
    agent.addListener(() => states.add(agent.state));
    if (stopAfterMs != null) {
      Future<void>.delayed(Duration(milliseconds: stopAfterMs), agent.stop);
    }
    await agent.send('週末、箱根で温泉旅行を計画して');
    agent.dispose();
    return states;
  }

  test('ストリーミングが Loading → Partial* → Ideal の順で流れる', () async {
    final states = await run(MockScenario.success);
    expect(states.first, isA<AiLoading>());
    expect(states.whereType<AiPartial>(), isNotEmpty);
    expect(states.last, isA<AiIdeal>());
    final firstPartial = states.indexWhere((s) => s is AiPartial);
    expect(states.skip(firstPartial).whereType<AiLoading>(), isEmpty);
  });

  test('キャンセルすると Failed ではなく Partial で終わる', () async {
    final states = await run(MockScenario.success, stopAfterMs: 220);
    expect(states.last, isA<AiPartial>());
    expect((states.last as AiPartial).stoppedByUser, isTrue);
  });

  test('通信が切れても、途中までの出力を残して Failed になる', () async {
    final states = await run(MockScenario.networkError);
    final last = states.last;
    expect(last, isA<AiFailed>());
    expect((last as AiFailed).kind, AiFailureKind.network);
    expect(last.partialText, isNotEmpty);
  });

  test('返ってきても画面が組めなければ、成功ではなく低品質の失敗として扱う', () async {
    final states = await run(MockScenario.lowQuality);
    expect(
      states.last,
      isA<AiFailed>().having((s) => s.kind, 'kind', AiFailureKind.lowQuality),
    );
  });
}
