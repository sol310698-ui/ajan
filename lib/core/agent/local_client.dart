import 'dart:async';

import 'package:fllama/fllama.dart' as fl;

import '../../models/chat_message.dart';
import 'llm_client.dart';

/// Cihaz uzerinde (offline) GGUF modeli calistiran istemci (llama.cpp / fllama).
///
/// Kucuk yerel modeller function calling'de zayif oldugu icin araclar
/// gonderilmez; offline modda ajan sohbet-odakli calisir. Inference native
/// tarafta ayri thread'de kosar; UI donmaz.
class LocalClient extends LlmClient {
  LocalClient({required String modelPath})
      : super(apiKey: '', model: modelPath, maxRetries: 1);

  @override
  Future<ChatMessage> send({
    required List<ChatMessage> history,
    required String systemPrompt,
    required List<Map<String, dynamic>> toolDeclarations,
  }) async {
    if (model.trim().isEmpty) {
      return ChatMessage(
        role: Role.assistant,
        text: 'Yerel model secili degil. "Yerel modeller"den bir model '
            'indirip aktif yap.',
      );
    }

    final messages = <fl.Message>[fl.Message(fl.Role.system, systemPrompt)];
    for (final m in history) {
      switch (m.role) {
        case Role.user:
          messages.add(fl.Message(fl.Role.user, m.text));
          break;
        case Role.assistant:
          if (m.text.isNotEmpty) {
            messages.add(fl.Message(fl.Role.assistant, m.text));
          }
          break;
        case Role.tool:
          final r = m.toolResult!;
          messages.add(fl.Message(
              fl.Role.user, 'Arac sonucu (${r.name}): ${r.output}'));
          break;
        case Role.system:
          break;
      }
    }

    final request = fl.OpenAiRequest(
      modelPath: model,
      messages: messages,
      contextSize: 4096,
      maxTokens: 512,
      numGpuLayers: 99, // GPU'ya yukle (donma/isinma az)
      temperature: 0.4,
      topP: 1.0,
      frequencyPenalty: 0.0,
      presencePenalty: 0.0,
      logger: (_) {},
    );

    final completer = Completer<String>();
    var last = '';
    try {
      await fl.fllamaChat(request, (response, done) {
        last = response;
        if (done && !completer.isCompleted) completer.complete(response);
      });
    } catch (e) {
      if (!completer.isCompleted) completer.complete('Yerel model hatasi: $e');
    }
    final text = await completer.future
        .timeout(const Duration(minutes: 3), onTimeout: () => last);
    return ChatMessage(
      role: Role.assistant,
      text: text.trim().isEmpty ? '(yerel model bos yanit verdi)' : text.trim(),
    );
  }
}
