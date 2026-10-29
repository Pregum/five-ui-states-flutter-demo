import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

String? readEnv(String name) {
  final env = Platform.environment[name];
  if (env != null && env.isNotEmpty) return env;
  final file = File('.env');
  if (!file.existsSync()) return null;
  for (final line in file.readAsLinesSync()) {
    final m = RegExp('^\\s*$name\\s*=\\s*(.+?)\\s*\$').firstMatch(line);
    if (m != null) return m.group(1)!.replaceAll(RegExp(r'''^["']|["']$'''), '');
  }
  return null;
}

String? arg(List<String> args, String name) {
  final i = args.indexOf(name);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 次の 1 分枠の 3 秒目まで待ち、その枠の開始時刻を返す。
Future<DateTime> waitForNextMinute() async {
  final now = DateTime.now();
  final next = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
  await Future<void>.delayed(next.difference(now) + const Duration(seconds: 3));
  return next;
}

/// 利用量 API（1 分単位）から各試行の課金トークンを取り、結果ファイルに書き足して表を出す。
Future<void> fillUsage(File file, {required String adminKey}) async {
  final result = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final model = result['model'] as String;
  final trials = (result['trials'] as List).cast<Map<String, dynamic>>();
  final starts = trials.map((t) => t['minuteStart'] as int);
  final from = starts.reduce((a, b) => a < b ? a : b);
  final to = starts.reduce((a, b) => a > b ? a : b) + 60;

  final byMinute = <int, Map<String, int>>{};
  String? page;
  do {
    final q = {
      'start_time': '$from',
      'end_time': '$to',
      'bucket_width': '1m',
      'limit': '1440',
      'models': model,
      if (page != null) 'page': page,
    };
    final res = await http.get(
      Uri.https('api.openai.com', '/v1/organization/usage/completions', q),
      headers: {'Authorization': 'Bearer $adminKey'},
    );
    if (res.statusCode != 200) throw '利用量 API HTTP ${res.statusCode}: ${res.body}';
    final d = jsonDecode(res.body) as Map<String, dynamic>;
    for (final b in (d['data'] as List).cast<Map<String, dynamic>>()) {
      for (final r in (b['results'] as List).cast<Map<String, dynamic>>()) {
        final m = byMinute.putIfAbsent(b['start_time'] as int, () => {'req': 0, 'in': 0, 'out': 0});
        m['req'] = m['req']! + (r['num_model_requests'] as int);
        m['in'] = m['in']! + (r['input_tokens'] as int);
        m['out'] = m['out']! + (r['output_tokens'] as int);
      }
    }
    page = d['has_more'] == true ? d['next_page'] as String? : null;
  } while (page != null);

  for (final t in trials) {
    final u = byMinute[t['minuteStart']];
    t['billedRequests'] = u?['req'] ?? 0;
    t['billedInputTokens'] = u?['in'] ?? 0;
    t['billedOutputTokens'] = u?['out'] ?? 0;
  }
  result['usageFetchedAt'] = DateTime.now().toIso8601String();
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));

  // 最後まで受け取った回から、1 行あたりのトークン数を求める
  final full = trials.where((t) => t['streamOutputTokens'] != null && (t['receivedLines'] ?? 0) > 0);
  final perLine = full.isEmpty
      ? null
      : full.map((t) => (t['streamOutputTokens'] as int) / (t['receivedLines'] as int)).reduce((a, b) => a + b) /
          full.length;

  stdout.writeln('\n=== 結果（${file.path}）===');
  if (perLine != null) stdout.writeln('1 行あたり ${perLine.toStringAsFixed(2)} トークン');
  stdout.writeln('時刻 | 条件 | 最初の差分→中断 | 受信行 | 受信トークン(推定) | 課金リクエスト | 課金 output_tokens');
  for (final t in trials) {
    final lines = t['receivedLines'] as int? ?? 0;
    final received = perLine == null ? '-' : '${(lines * perLine).round()}';
    final first = t['firstDeltaMs'] as int?;
    final stop = t['stoppedAtMs'] as int?;
    final span = (first == null || stop == null) ? '-' : '${((stop - first) / 1000).toStringAsFixed(1)}s';
    stdout.writeln('${hhmm(DateTime.fromMillisecondsSinceEpoch((t['minuteStart'] as int) * 1000))} | '
        '${t['condition']} | $span | $lines | $received | ${t['billedRequests']} | ${t['billedOutputTokens']}'
        '${t['completedBeforeStop'] == true ? '  (中断前に完了)' : ''}${t['error'] == null ? '' : '  (${t['error']})'}');
  }
}
