import '../../models/chat_message.dart';
import 'llm_client.dart';
import 'tool_registry.dart';

/// Ajanin karar dongusu.
///
/// Akis:
///  1. Kullanici mesaji gecmise eklenir.
///  2. LLM cagrilir.
///  3. LLM arac cagirdiysa -> araclar calistirilir, sonuclar gecmise
///     eklenir, tekrar LLM cagrilir (2'ye don).
///  4. LLM duz metin dondururse -> nihai cevap, dongu biter.
///
/// [maxSteps] sonsuz donguye karsi guvenlik siniri.
class AgentLoop {
  final LlmClient llm;
  final ToolRegistry registry;
  final String systemPrompt;
  final int maxSteps;

  AgentLoop({
    required this.llm,
    required this.registry,
    required this.systemPrompt,
    this.maxSteps = 8,
  });

  /// Her adimda UI'yi guncellemek icin cagrilir (yeni mesajlar akar).
  /// onEvent, gecmise eklenen her mesajla tetiklenir.
  Future<void> run(
    List<ChatMessage> history, {
    required void Function(ChatMessage) onEvent,
  }) async {
    for (var step = 0; step < maxSteps; step++) {
      final reply = await llm.send(
        history: history,
        systemPrompt: systemPrompt,
        toolDeclarations: registry.declarations,
      );

      history.add(reply);
      onEvent(reply);

      // Arac cagrisi yoksa nihai cevap alindi -> bitir.
      if (!reply.hasToolCalls) return;

      // Cagrilan tum araclari calistir, sonuclari gecmise ekle.
      for (final call in reply.toolCalls) {
        final tool = registry.byName(call.name);
        final ToolResult result;
        if (tool == null) {
          result = ToolResult(
            callId: call.id,
            name: call.name,
            ok: false,
            output: 'Bilinmeyen arac: ${call.name}',
          );
        } else {
          try {
            final output = await tool.run(call.args);
            result = ToolResult(
              callId: call.id,
              name: call.name,
              ok: true,
              output: output,
            );
          } catch (e) {
            result = ToolResult(
              callId: call.id,
              name: call.name,
              ok: false,
              output: 'Arac hatasi: $e',
            );
          }
        }
        final toolMsg = ChatMessage(role: Role.tool, toolResult: result);
        history.add(toolMsg);
        onEvent(toolMsg);
      }
    }

    // Guvenlik siniri asildi.
    final stop = ChatMessage(
      role: Role.assistant,
      text: 'Adim siniri asildi ($maxSteps). Islem durduruldu.',
    );
    history.add(stop);
    onEvent(stop);
  }
}
