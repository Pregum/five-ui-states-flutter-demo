// 実験結果ファイルに、利用量 API の課金トークンを取り直して書き足す。
//   dart run bin/usage.dart results/<日時>.json
import 'dart:io';

import 'common.dart';

Future<void> main(List<String> args) async {
  final adminKey = readEnv('OPENAI_ADMIN_KEY');
  if (args.isEmpty || adminKey == null) {
    stderr.writeln('使い方: dart run bin/usage.dart results/<日時>.json（.env に OPENAI_ADMIN_KEY が必要）');
    exit(64);
  }
  await fillUsage(File(args.first), adminKey: adminKey);
}
