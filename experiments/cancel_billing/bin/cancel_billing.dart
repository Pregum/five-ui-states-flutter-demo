// ストリーミング応答を途中で中断したとき、何トークン課金されるかを調べる。
//
// やること：
//   1. Responses API に「1 から N まで 1 行ずつ数字を書いて」と頼み、ストリーミングで受け取る
//   2. 最初の差分から決めた秒数がたった時点で中断する（Flutter アプリと同じく StreamSubscription.cancel()）
//   3. 1 回ずつ別の 1 分枠で実行し、あとで利用量 API（1 分単位）で課金トークンを突き合わせる
//
// 途中で中断した応答はサーバーに保存されず GET /v1/responses/{id} で取り直せないため、
// 課金トークンは管理者キーで利用量 API から取る。
//
// 使い方（.env に OPENAI_API_KEY と OPENAI_ADMIN_KEY を書いておく）：
//   dart run bin/cancel_billing.dart [--reps 3] [--model gpt-6-luna] [--effort none]
//   dart run bin/usage.dart results/<日時>.json   … 利用量だけ取り直す（反映が遅れたとき）

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'common.dart';

const totalLines = 1200;
const prompt =
    'Output the integers from 1 to $totalLines, one per line, in ascending order. '
    'Output nothing else: no introduction, no code block, no closing remark.';

class Condition {
  const Condition(this.label, this.stopAfter, {this.close = false});
  final String label;

  /// 最初の差分からこの時間がたったら中断する。null なら最後まで受け取る。
  final Duration? stopAfter;

  /// 中断時に client.close() もするか
  final bool close;
}

const conditions = [
  Condition('最後まで', null),
  Condition('最初の差分で中断', Duration.zero),
  Condition('1 秒後に中断', Duration(seconds: 1)),
  Condition('2 秒後に中断', Duration(seconds: 2)),
  Condition('2 秒後に中断 + close', Duration(seconds: 2), close: true),
  Condition('6 秒後に中断', Duration(seconds: 6)),
];

Future<void> main(List<String> args) async {
  final apiKey = readEnv('OPENAI_API_KEY');
  final adminKey = readEnv('OPENAI_ADMIN_KEY');
  if (apiKey == null || adminKey == null) {
    stderr.writeln('.env に OPENAI_API_KEY と OPENAI_ADMIN_KEY を設定してください。');
    exit(64);
  }
  final reps = int.parse(arg(args, '--reps') ?? '3');
  final model = arg(args, '--model') ?? 'gpt-6-luna';
  final effort = arg(args, '--effort') ?? 'none';
  stdout.writeln('model=$model effort=$effort reps=$reps（1 回ごとに次の 1 分枠を待つ）');

  final trials = <Map<String, Object?>>[];
  for (var rep = 1; rep <= reps; rep++) {
    for (final c in conditions) {
      final minute = await waitForNextMinute();
      stdout.write('[${hhmm(minute)}] ($rep) ${c.label} ... ');
      final t = <String, Object?>{
        'condition': c.label,
        'rep': rep,
        'minuteStart': minute.millisecondsSinceEpoch ~/ 1000,
      };
      try {
        await _run(t, c, apiKey: apiKey, model: model, effort: effort);
        stdout.writeln('受信 ${t['receivedLines']} 行 / ${t['receivedDeltas']} 差分'
            '${t['streamOutputTokens'] == null ? '' : ' / 完了 output_tokens=${t['streamOutputTokens']}'}');
      } catch (e) {
        t['error'] = '$e';
        stdout.writeln('失敗: $e');
      }
      trials.add(t);
    }
  }

  final dir = Directory('results')..createSync(recursive: true);
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
  final file = File('${dir.path}/$stamp.json');
  final result = {'model': model, 'effort': effort, 'totalLines': totalLines, 'trials': trials};
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  stdout.writeln('\n受信結果を ${file.path} に保存しました。利用量の反映を 3 分待ちます…');

  await Future<void>.delayed(const Duration(minutes: 3));
  await fillUsage(file, adminKey: adminKey);
}

Future<void> _run(
  Map<String, Object?> t,
  Condition c, {
  required String apiKey,
  required String model,
  required String effort,
}) async {
  final client = http.Client();
  final request = http.Request('POST', Uri.parse('https://api.openai.com/v1/responses'))
    ..headers.addAll({'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'})
    ..body = jsonEncode({
      'model': model,
      'input': prompt,
      'stream': true,
      'store': false,
      'max_output_tokens': 4000,
      'reasoning': {'effort': effort},
    });

  final watch = Stopwatch()..start();
  final response = await client.send(request);
  if (response.statusCode != 200) {
    final body = await response.stream.bytesToString();
    client.close();
    throw 'HTTP ${response.statusCode}: $body';
  }

  final done = Completer<void>();
  final text = StringBuffer();
  var deltas = 0;
  Duration? firstDeltaAt;
  Timer? timer;
  late final StreamSubscription<String> sub;

  void record() {
    t['receivedDeltas'] = deltas;
    t['receivedLines'] = '\n'.allMatches(text.toString()).length;
    t['receivedChars'] = text.length;
  }

  Future<void> stopNow() async {
    if (done.isCompleted) return;
    record();
    t['stoppedAtMs'] = watch.elapsedMilliseconds;
    t['firstDeltaMs'] = firstDeltaAt?.inMilliseconds;
    done.complete();
    await sub.cancel();
    if (c.close) client.close();
  }

  sub = response.stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    if (!line.startsWith('data: ')) return;
    final event = jsonDecode(line.substring(6)) as Map<String, dynamic>;
    switch (event['type']) {
      case 'response.output_text.delta':
        deltas++;
        text.write(event['delta'] as String);
        if (firstDeltaAt == null) {
          firstDeltaAt = watch.elapsed;
          final after = c.stopAfter;
          if (after == Duration.zero) {
            stopNow();
          } else if (after != null) {
            timer = Timer(after, stopNow);
          }
        }
      case 'response.completed':
        final usage = (event['response'] as Map)['usage'] as Map?;
        t['streamOutputTokens'] = usage?['output_tokens'];
    }
  }, onDone: () {
    timer?.cancel();
    if (!done.isCompleted) {
      record();
      t['stoppedAtMs'] = watch.elapsedMilliseconds;
      t['firstDeltaMs'] = firstDeltaAt?.inMilliseconds;
      t['completedBeforeStop'] = c.stopAfter != null;
      done.complete();
    }
  }, onError: (Object e) {
    if (!done.isCompleted) done.completeError(e);
  });

  await done.future;
  // cancel だけのときは、この 1 分枠が終わるまで client を開いたままにしておく（close し忘れた状況）
  if (!c.close) {
    Future<void>.delayed(const Duration(seconds: 50), client.close);
  }
}
