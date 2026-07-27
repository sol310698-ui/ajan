import '../../models/chat_message.dart';
import '../settings.dart';
import 'agent_loop.dart';
import 'llm_client.dart';
import 'system_prompt.dart';
import 'tool_registry.dart';

/// Tek bir istegi (prompt) ajan dongusunden gecirir ve nihai metni dondurur.
///
/// Sohbet arayuzunden bagimsizdir; rutinler / arka plan gorevleri bunu kullanir.
Future<String> runAgentOnce(String prompt, {int maxSteps = 20}) async {
  final settings = await AppSettings.load();
  if (!settings.hasKey) {
    return 'API anahtari ayarli degil; rutin calistirilamadi.';
  }

  final llm = LlmClient.create(
    provider: settings.provider,
    apiKey: settings.apiKey,
    model: settings.model,
  );
  final loop = AgentLoop(
    llm: llm,
    registry: ToolRegistry(),
    systemPrompt: await buildSystemPrompt(),
    maxSteps: maxSteps,
  );

  final history = <ChatMessage>[ChatMessage(role: Role.user, text: prompt)];
  var finalText = '';
  await loop.run(
    history,
    onEvent: (m) {
      if (m.role == Role.assistant && m.text.trim().isNotEmpty) {
        finalText = m.text.trim();
      }
    },
  );
  return finalText.isEmpty ? '(rutin tamamlandi, metin cevabi yok)' : finalText;
}
