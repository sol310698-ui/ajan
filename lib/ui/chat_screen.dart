import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/voice/voice_service.dart';
import '../models/chat_message.dart';
import '../providers/agent_provider.dart';
import 'alarms_screen.dart';
import 'local_models_screen.dart';
import 'memory_screen.dart';
import 'routines_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
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
      backgroundColor: AppColors.bg,
      drawer: _buildDrawer(state),
      appBar: AppBar(
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.brand),
        ),
        title: Text(state.current?.title ?? 'Ajan',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (!state.hasKey)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.key_off, color: Colors.amberAccent),
            ),
          if (voice.speaking)
            IconButton(
              icon: const Icon(Icons.volume_off),
              tooltip: 'Susturmayi durdur',
              onPressed: () => ref.read(voiceProvider.notifier).stopSpeaking(),
            ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'Yeni sohbet',
            onPressed: () => ref.read(agentProvider.notifier).newConversation(),
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
              color: AppColors.primary,
              backgroundColor: AppColors.surface,
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

  Widget _buildDrawer(AgentState state) {
    final notifier = ref.read(agentProvider.notifier);
    return Drawer(
      backgroundColor: const Color(0xFF11111B),
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.smart_toy_outlined, color: Color(0xFF6C5CE7)),
                  SizedBox(width: 10),
                  Text('Ajan',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add, color: Color(0xFF6C5CE7)),
              title: const Text('Yeni sohbet',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                notifier.newConversation();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.alarm, color: Color(0xFF6C5CE7)),
              title: const Text('Alarmlar',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AlarmsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule, color: Color(0xFF6C5CE7)),
              title: const Text('Rutinler',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RoutinesScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.psychology, color: Color(0xFF6C5CE7)),
              title:
                  const Text('Hafiza', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const MemoryScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline,
                  color: Color(0xFF6C5CE7)),
              title: const Text('Yerel modeller',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LocalModelsScreen()));
              },
            ),
            const Divider(color: Color(0xFF2A2A3A)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Sohbetler',
                    style: TextStyle(color: Color(0xFF6E6C8A), fontSize: 13)),
              ),
            ),
            Expanded(
              child: ListView(
                children: state.conversations.map((c) {
                  final selected = c.id == state.currentId;
                  return ListTile(
                    selected: selected,
                    selectedTileColor: const Color(0xFF1E1E2E),
                    title: Text(c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: selected
                                ? Colors.white
                                : const Color(0xFFB9B7CE))),
                    onTap: () {
                      notifier.switchConversation(c.id);
                      Navigator.pop(context);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: Color(0xFF6E6C8A)),
                      onPressed: () => notifier.deleteConversation(c.id),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.brand,
              ),
              child: const Icon(Icons.smart_toy_outlined,
                  size: 48, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text(
              'Merhaba, ben senin ajaninim',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bir sey sor, sesle konus ya da bir is ver.\n'
              'Ornek: "hava durumu Istanbul", "pil durumu", '
              '"her sabah 8de gundem ozeti".',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textFaint, fontSize: 14),
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
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Color(0xFF20202E))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: Icon(listening ? Icons.mic : Icons.mic_none,
                  color:
                      listening ? Colors.redAccent : AppColors.primaryLight),
              onPressed: onMic,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 5,
                style: const TextStyle(color: AppColors.textPrimary),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: listening ? 'Dinliyorum...' : 'Mesaj...',
                  hintStyle: const TextStyle(color: AppColors.textFaint),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(26),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: enabled ? onSend : null,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: enabled ? AppColors.brand : null,
                  color: enabled ? null : AppColors.card,
                ),
                child: Icon(Icons.send,
                    color: enabled ? Colors.white : AppColors.textFaint,
                    size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
