import '../../models/chat_message.dart';
import '../local/gemma_engine.dart';
import 'llm_client.dart';

/// Cihaz uzerinde (offline) model calistiran istemci (flutter_gemma/MediaPipe).
///
/// Kucuk yerel modeller function calling'de zayif oldugu icin araclar
/// gonderilmez; offline modda ajan sohbet-odakli calisir.
class LocalClient extends LlmClient {
  LocalClient({required String modelPath})
      : super(apiKey: '', model: modelPath, maxRetries: 1);

  @override
  Future<ChatMessage> send({
    required List<ChatMessage> history,
    required String systemPrompt,
    required List<Map<String, dynamic>> toolDeclarations,
  }) async {
    if (!await gemmaEngine.isInstalled()) {
      return ChatMessage(
        role: Role.assistant,
        text: 'Offline model kurulu degil. "Yerel modeller" ekranindan '
            'offline modeli indir/kur.',
      );
    }

    final turns = <GemmaTurn>[];
    for (final m in history) {
      switch (m.role) {
        case Role.user:
          turns.add(GemmaTurn(m.text, true));
          break;
        case Role.assistant:
          if (m.text.isNotEmpty) turns.add(GemmaTurn(m.text, false));
          break;
        case Role.tool:
          final r = m.toolResult!;
          turns.add(GemmaTurn('Arac sonucu (${r.name}): ${r.output}', true));
          break;
        case Role.system:
          break;
      }
    }

    // Kucuk yerel model icin KISA sistem talimati (dev agent talimati agir).
    const shortSystem =
        'Sen Turkce konusan, kisa ve net cevap veren yardimci bir asistansin.';
    final text = await gemmaEngine.ask(shortSystem, turns);
    return ChatMessage(
      role: Role.assistant,
      text: text.isEmpty ? '(yerel model bos yanit verdi)' : text,
    );
  }
}
