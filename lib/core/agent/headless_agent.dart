import 'dart:io';

import '../../models/chat_message.dart';
import '../local/local_model_store.dart';
import '../settings.dart';
import 'agent_loop.dart';
import 'llm_client.dart';
import 'system_prompt.dart';
import 'tool_registry.dart';

Future<bool> _hasInternet() async {
  try {
    final r = await InternetAddress.lookup('generativelanguage.googleapis.com')
        .timeout(const Duration(seconds: 3));
    return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Tek bir istegi (prompt) ajan dongusunden gecirir ve nihai metni dondurur.
///
/// Sohbet arayuzunden bagimsizdir; rutinler / arka plan gorevleri bunu kullanir.
/// Cevrimdisiysa (veya saglayici Yerel'se) aktif yerel modele duser.
Future<String> runAgentOnce(
  String prompt, {
  int maxSteps = 20,
  bool chatOnly = false,
}) async {
  final settings = await AppSettings.load();

  var provider = settings.provider;
  var model = settings.model;
  var chat = chatOnly;

  if (provider == LlmProvider.local) {
    model = await LocalModelStore().activeModelPath();
    chat = true;
  } else if (!settings.hasKey || !await _hasInternet()) {
    final p = await LocalModelStore().activeModelPath();
    if (p.isNotEmpty) {
      provider = LlmProvider.local;
      model = p;
      chat = true;
    }
  }

  final ready =
      provider == LlmProvider.local ? model.isNotEmpty : settings.hasKey;
  if (!ready) {
    return 'API anahtari yok ve yerel model de yok; calistirilamadi.';
  }

  final llm = LlmClient.create(
    provider: provider,
    apiKey: settings.apiKey,
    model: model,
    googleSearch: settings.googleSearch,
  );
  final loop = AgentLoop(
    llm: llm,
    registry: ToolRegistry(chatOnly: chat),
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
