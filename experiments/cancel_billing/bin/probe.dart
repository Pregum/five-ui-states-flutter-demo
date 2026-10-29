// 1 リクエストだけ送り、イベントの到着時刻と中断後のふるまいを細かく記録する調査用スクリプト。
//   dart run bin/probe.dart <中断する行数（0 なら最初の差分、-1 なら中断しない）>
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final stopAt = int.parse(args.isEmpty ? '300' : args[0]);
  final key = File('.env')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('OPENAI_API_KEY='))
      .split('=')
      .skip(1)
      .join('=')
      .trim();
  final client = http.Client();
  final req = http.Request('POST', Uri.parse('https://api.openai.com/v1/responses'))
    ..headers.addAll({'Authorization': 'Bearer $key', 'Content-Type': 'application/json'})
    ..body = jsonEncode({
      'model': 'gpt-6-luna',
      'input': 'Output the integers from 1 to 1200, one per line, in ascending order. Output nothing else.',
      'stream': true,
      'store': true,
      'max_output_tokens': 4000,
      'reasoning': {'effort': 'none'},
    });
  final w = Stopwatch()..start();
  void log(String s) => stdout.writeln('${w.elapsedMilliseconds.toString().padLeft(6)}ms  $s');

  final res = await client.send(req);
  log('HTTP ${res.statusCode}');
  String? id;
  var lines = 0, deltas = 0, afterCancelEvents = 0, bytes = 0;
  var stopped = false;
  final text = StringBuffer();
  final done = Completer<void>();
  late StreamSubscription<String> sub;
  sub = res.stream
      .map((chunk) {
        bytes += chunk.length;
        return chunk;
      })
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    if (stopped) afterCancelEvents++;
    if (!line.startsWith('data: ')) return;
    final e = jsonDecode(line.substring(6)) as Map<String, dynamic>;
    final type = e['type'];
    if (type == 'response.created') {
      id = (e['response'] as Map)['id'] as String;
      log('created id=$id');
    } else if (type == 'response.output_text.delta') {
      deltas++;
      text.write(e['delta']);
      final n = '\n'.allMatches(text.toString()).length;
      if (deltas == 1) log('first delta');
      if (n ~/ 200 != lines ~/ 200) log('lines=$n bytes=$bytes');
      lines = n;
      if (!stopped && stopAt >= 0 && lines >= stopAt) {
        stopped = true;
        log('CANCEL at lines=$lines deltas=$deltas bytes=$bytes');
        sub.cancel().then((_) {
          log('cancel() completed');
          if (!done.isCompleted) done.complete();
        });
      }
    } else if (type == 'response.completed') {
      final u = (e['response'] as Map)['usage'];
      log('completed usage=$u');
    }
  }, onDone: () {
    log('stream done');
    if (!done.isCompleted) done.complete();
  });
  await done.future;
  log('afterCancelEvents=$afterCancelEvents (中断後に処理されたイベント数)');
  client.close();

  for (final wait in [2, 10, 30]) {
    await Future<void>.delayed(Duration(seconds: wait));
    final g = await http.get(Uri.parse('https://api.openai.com/v1/responses/$id'),
        headers: {'Authorization': 'Bearer $key'});
    final body = g.body;
    Map<String, dynamic>? j;
    try {
      j = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}
    log('GET HTTP ${g.statusCode} status=${j?['status']} usage=${j?['usage']} '
        'incomplete=${j?['incomplete_details']} error=${j?['error']}');
  }
}
