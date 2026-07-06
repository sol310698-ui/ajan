import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/native/automation.dart';
import '../core/voice/voice_service.dart';
import '../models/chat_message.dart';
import '../providers/agent_provider.dart';
import 'widgets/message_widgets.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(voiceProvider.notifier).stopSpeaking();
    ref.read(agentProvider.notifier).sendUserMessage(text);
    _scrollDown();
  }

  void _toggleMic() {
    final voice = ref.read(voiceProvider);
    final vc = ref.read(voiceProvider.notifier);
    if (voice.listening) {
      vc.stopListening();
    } else {
      vc.startListening((text) {
        _input.text = text;
        _input.selection =
            TextSelection.collapsed(offset: _input.text.length);
      });
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  int _spokenCount = 0;

  /// Yeni gelen her asistan metnini (ara adimlar dahil) sirayla seslendirir.
  void _maybeSpeak(AgentState? prev, AgentState next) {
    if (!ref.read(voiceProvider).autoSpeak) {
      _spokenCount = next.messages.length;
      return;
    }
    // Sohbet temizlendiyse sayaci sifirla.
    if (next.messages.length < _spokenCount) _spokenCount = 0;
    final vc = ref.read(voiceProvider.notifier);
    for (var i = _spokenCount; i < next.messages.length; i++) {
      final m = next.messages[i];
      if (m.role == Role.assistant && m.text.trim().isNotEmpty) {
        vc.speak(m.text);
      }
    }
    _spokenCount = next.messages.length;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentProvider);
    final voice = ref.watch(voiceProvider);
    ref.listen(agentProvider, (prev, next) {
      _scrollDown();
      _maybeSpeak(prev, next);
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11111B),
        title: const Text('Ajan'),
        actions: [
          if (!state.hasKey)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.key_off, color: Colors.orangeAccent),
            ),
          if (voice.speaking)
            IconButton(
              icon: const Icon(Icons.volume_off),
              tooltip: 'Susturmayi durdur',
              onPressed: () => ref.read(voiceProvider.notifier).stopSpeaking(),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => ref.read(agentProvider.notifier).clearChat(),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: state.messages.isEmpty
                ? const _EmptyHint()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.messages.length,
                    itemBuilder: (_, i) =>
                        MessageBubble(message: state.messages[i]),
                  ),
          ),
          if (state.busy)
            const LinearProgressIndicator(
              color: Color(0xFF6C5CE7),
              backgroundColor: Color(0xFF11111B),
            ),
          _InputBar(
            controller: _input,
            onSend: _send,
            enabled: !state.busy,
            listening: voice.listening,
            onMic: _toggleMic,
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    final notifier = ref.read(agentProvider.notifier);
    final keyCtrl = TextEditingController();
    final modelCtrl = TextEditingController(text: notifier.model);
    showDialog(
      context: context,
      builder: (_) => Consumer(builder: (ctx, r, __) {
        final voice = r.watch(voiceProvider);
        final vc = r.read(voiceProvider.notifier);
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('Ayarlar', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: keyCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Gemini API Anahtari',
                    hintText: 'AIza...',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Model'),
                ),
                const SizedBox(height: 20),
                const Text('Ses', style: TextStyle(color: Color(0xFF9E9CB8))),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cevaplari sesli oku',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  value: voice.autoSpeak,
                  activeColor: const Color(0xFF6C5CE7),
                  onChanged: (v) => vc.setAutoSpeak(v),
                ),
                Text('Konusma hizi: ${voice.rate.toStringAsFixed(2)}',
                    style:
                        const TextStyle(color: Colors.white, fontSize: 13)),
                Slider(
                  min: 0.2,
                  max: 1.0,
                  divisions: 16,
                  value: voice.rate.clamp(0.2, 1.0),
                  activeColor: const Color(0xFF6C5CE7),
                  label: voice.rate.toStringAsFixed(2),
                  onChanged: (v) => vc.setRate(v),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Dene'),
                    onPressed: () =>
                        vc.speak('Merhaba, ben senin ajaninim. Bu bir hiz denemesi.'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Ekran kontrolu',
                    style: TextStyle(color: Color(0xFF9E9CB8))),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  icon: const Icon(Icons.accessibility_new, size: 18),
                  label: const Text('Erisilebilirligi ac'),
                  onPressed: () => Automation.openAccessibilitySettings(),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.bubble_chart, size: 18),
                        label: const Text('Yuzen buton'),
                        onPressed: () async {
                          if (!await Automation.hasOverlayPermission()) {
                            await Automation.requestOverlayPermission();
                          } else {
                            await Automation.overlayStart();
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      tooltip: 'Yuzen butonu kapat',
                      onPressed: () => Automation.overlayStop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
            FilledButton(
              onPressed: () {
                notifier.saveKey(keyCtrl.text, model: modelCtrl.text);
                Navigator.pop(ctx);
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      }),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 64, color: Color(0xFF6C5CE7)),
            SizedBox(height: 16),
            Text(
              'Bir sey sor, sesle konus veya bir is ver.\n'
              'Mikrofona basip konusabilirsin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6E6C8A), fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onMic;
  final bool enabled;
  final bool listening;
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.onMic,
    required this.enabled,
    required this.listening,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      color: const Color(0xFF11111B),
      child: Row(
        children: [
          IconButton(
            icon: Icon(listening ? Icons.mic : Icons.mic_none,
                color: listening ? Colors.redAccent : const Color(0xFF6C5CE7)),
            onPressed: onMic,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 5,
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: listening ? 'Dinliyorum...' : 'Mesaj...',
                hintStyle: const TextStyle(color: Color(0xFF6E6C8A)),
                filled: true,
                fillColor: const Color(0xFF1E1E2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          CircleAvatar(
            backgroundColor: const Color(0xFF6C5CE7),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: enabled ? onSend : null,
            ),
          ),
        ],
      ),
    );
  }
}
