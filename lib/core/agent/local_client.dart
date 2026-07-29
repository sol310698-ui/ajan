import '../../models/chat_message.dart';
import 'llm_client.dart';

/// Cihaz uzerinde (offline) model calistiran istemci.
///
/// NOT: Native calistirma motoru (llama.cpp/fllama) tum llama.cpp'yi derledigi
/// icin APK'yi cok buyutuyordu ve "az kaynak" hedefine ters dustu; bu surumde
/// bundlanmadi. Model INDIRME/YONETIM (Yerel modeller ekrani) calisir; motor
/// daha hafif bir cozumle (MediaPipe/Gemini Nano) ileride baglanacak.
class LocalClient extends LlmClient {
  LocalClient({required String modelPath})
      : super(apiKey: '', model: modelPath, maxRetries: 1);

  @override
  Future<ChatMessage> send({
    required List<ChatMessage> history,
    required String systemPrompt,
    required List<Map<String, dynamic>> toolDeclarations,
  }) async {
    return ChatMessage(
      role: Role.assistant,
      text: model.trim().isEmpty
          ? 'Yerel model secili degil. "Yerel modeller"den bir model indir.'
          : 'Yerel calistirma motoru bu surumde henuz aktif degil '
              '(model indirildi ama motor baglanmadi). Simdilik internet '
              'gerektiren bir saglayici (Gemini/OpenAI/Claude) kullan.',
    );
  }
}
