import 'dart:async';
import 'dart:convert';

import '../catalog/travel_catalog.dart';
import 'backend.dart';

/// モックで再現する筋書き。
enum MockScenario {
  /// 最後まで届く。
  success('最後まで届く'),

  /// 途中で通信が切れる。
  networkError('途中で通信が切れる'),

  /// 返ってくるが、画面を組めない短い返事だけ。
  lowQuality('中身のない返事'),

  /// 最初の 1 文字まで 20 秒以上かかる。
  slow('とても遅い');

  const MockScenario(this.label);

  final String label;
}

/// API を叩かずに、旅の相談の応答を時間差で再現する。
///
/// 届き方は、中断時の課金の実験で見た「最初は少しずつ → 止まる → まとめて届く」
/// ではなく、画面が育っていく様子が見えるよう 1 部品ずつ流している。
class MockBackend implements AgentBackend {
  MockBackend({required this.scenario, this.speed = 1.0});

  final MockScenario scenario;

  /// 1.0 で台本どおり。2.0 なら 2 倍速。
  final double speed;

  @override
  Stream<AgentEvent> run({
    required String systemPrompt,
    required List<({String role, String text})> history,
    required String prompt,
    required CancelToken cancel,
  }) async* {
    Future<bool> wait(int ms) async {
      await Future.any([
        Future<void>.delayed(Duration(milliseconds: (ms / speed).round())),
        cancel.whenCancelled,
      ]);
      return !cancel.isCancelled;
    }

    final steps = [
      ('依頼を受け取りました', 0.1, 900),
      ('箱根の週末の天気を調べています', 0.3, 1600),
      ('宿を 24 件比べています', 0.55, 2200),
      ('旅程を組み立てています', 0.8, 1500),
    ];
    if (scenario == MockScenario.slow) {
      steps.insert(2, ('混み合っています。もう少しお待ちください', 0.45, 14000));
    }
    for (final (label, progress, ms) in steps) {
      yield AgentStep(label, progress: progress);
      if (!await wait(ms)) return;
    }

    if (scenario == MockScenario.lowQuality) {
      yield const AgentChunk('わかりました。');
      return;
    }

    var sent = 0;
    for (final chunk in _successChunks()) {
      if (scenario == MockScenario.networkError && sent == 4) {
        throw const AgentException(AgentExceptionKind.network, '通信が途切れました');
      }
      yield AgentChunk(chunk);
      sent++;
      if (!await wait(chunk.startsWith('```') ? 900 : 350)) return;
    }
  }
}

String _block(Map<String, Object?> message) =>
    '```json\n${jsonEncode(message)}\n```\n';

Map<String, Object?> _components(List<Map<String, Object?>> components) => {
  'version': 'v0.9',
  'updateComponents': {'surfaceId': 'plan', 'components': components},
};

/// 1 部品ずつ増えていく旅の提案。各ブロックは A2UI v0.9 のメッセージ。
List<String> _successChunks() {
  const title = {
    'id': 'title',
    'component': 'Text',
    'text': '箱根 1 泊 2 日のプラン',
    'variant': 'h3',
  };
  const day1 = {
    'id': 'day1',
    'component': 'PlanDay',
    'day': 1,
    'title': '大涌谷と温泉',
    'items': ['ロープウェイで大涌谷へ', '昼は駅前のそば屋', '夜は宿の露天風呂でゆっくり'],
  };
  const day2 = {
    'id': 'day2',
    'component': 'PlanDay',
    'day': 2,
    'title': '美術館めぐり',
    'items': ['彫刻の森美術館', '湯本で温泉まんじゅう', '15 時ごろ帰路へ'],
  };
  const hotel = {
    'id': 'hotel',
    'component': 'HotelCard',
    'name': 'ホテル箱根の森',
    'price': 12000,
    'rating': 4.5,
    'note': '露天風呂付きで、駅から送迎あり',
  };
  Map<String, Object?> root(List<String> children) => {
    'id': 'root',
    'component': 'Column',
    'children': children,
  };

  return [
    '週末の箱根、いいですね。',
    '晴れの予報なので、外を歩くプランにしました。気になるところは、変えたい点を教えてください。\n',
    _block({
      'version': 'v0.9',
      'createSurface': {'surfaceId': 'plan', 'catalogId': travelCatalogId},
    }),
    _block(
      _components([
        root(['title']),
        title,
      ]),
    ),
    _block(
      _components([
        root(['title', 'day1']),
        day1,
      ]),
    ),
    _block(
      _components([
        root(['title', 'day1', 'day2']),
        day2,
      ]),
    ),
    _block(
      _components([
        root(['title', 'day1', 'day2', 'hotel']),
        hotel,
      ]),
    ),
  ];
}
