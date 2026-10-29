import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'backend.dart';

/// Gemini API を REST（SSE）で叩く。
///
/// API キーは `--dart-define=GEMINI_API_KEY=...` で渡す。ファイルには置かない。
class GeminiBackend implements AgentBackend {
  GeminiBackend({
    required this.apiKey,
    this.model = const String.fromEnvironment(
      'GEMINI_MODEL',
      defaultValue: 'gemini-flash-latest',
    ),
    this.firstTokenTimeout = const Duration(seconds: 60),
  });

  final String apiKey;
  final String model;
  final Duration firstTokenTimeout;

  /// 録画用：届いた断片と、最初の送信からの経過ミリ秒。
  final List<({int ms, String text})> lastRecording = [];

  @override
  Stream<AgentEvent> run({
    required String systemPrompt,
    required List<({String role, String text})> history,
    required String prompt,
    required CancelToken cancel,
  }) async* {
    lastRecording.clear();
    final started = DateTime.now();
    final client = http.Client();
    unawaited(cancel.whenCancelled.then((_) => client.close()));

    yield const AgentStep('Gemini に依頼しました');

    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:streamGenerateContent',
      {'alt': 'sse'},
    );
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'contents': [
        for (final m in history)
          {
            'role': m.role,
            'parts': [
              {'text': m.text},
            ],
          },
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
    });

    final http.StreamedResponse response;
    try {
      final request = http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json'
        ..headers['x-goog-api-key'] = apiKey
        ..body = body;
      response = await client.send(request).timeout(firstTokenTimeout);
    } on TimeoutException {
      client.close();
      throw const AgentException(AgentExceptionKind.timeout, '応答がありません');
    } catch (e) {
      client.close();
      if (cancel.isCancelled) return;
      throw AgentException(AgentExceptionKind.network, '$e');
    }

    if (response.statusCode != 200) {
      final text = await response.stream.bytesToString();
      client.close();
      throw AgentException(
        AgentExceptionKind.network,
        'HTTP ${response.statusCode}: ${text.length > 200 ? text.substring(0, 200) : text}',
      );
    }

    var first = true;
    try {
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (cancel.isCancelled) break;
        if (!line.startsWith('data:')) continue;
        final json =
            jsonDecode(line.substring(5).trim()) as Map<String, Object?>;
        final candidates = json['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) continue;
        final parts =
            ((candidates.first as Map)['content'] as Map?)?['parts'] as List?;
        if (parts == null) continue;
        for (final p in parts) {
          final text = (p as Map)['text'] as String?;
          if (text == null || text.isEmpty) continue;
          if (first) {
            first = false;
            yield const AgentStep('画面を組み立てています');
          }
          lastRecording.add((
            ms: DateTime.now().difference(started).inMilliseconds,
            text: text,
          ));
          yield AgentChunk(text);
        }
      }
    } catch (e) {
      if (cancel.isCancelled) return;
      throw AgentException(AgentExceptionKind.network, '$e');
    } finally {
      client.close();
      if (kDebugMode && lastRecording.isNotEmpty) {
        debugPrint(
          'RECORDING ${jsonEncode([
            for (final r in lastRecording) {'ms': r.ms, 'text': r.text},
          ])}',
        );
      }
    }
  }
}
