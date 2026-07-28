import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/agent/llm_client.dart';
import '../core/native/automation.dart';
import '../core/voice/voice_service.dart';
import '../providers/agent_provider.dart';

/// Ayarlar penceresi: saglayici + anahtar + model (anahtar girilince
/// modeller API'den cekilip acilir menude gosterilir) + ses + ekran kontrolu.
class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});
  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  List<String> _models = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(agentProvider.notifier).settings;
    _keyCtrl.text = s.apiKey;
    _modelCtrl.text = s.model;
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _onProviderChanged(LlmProvider p) {
    final notifier = ref.read(agentProvider.notifier);
    notifier.saveSettings(provider: p);
    final s = notifier.settings;
    setState(() {
      _keyCtrl.text = s.apiKey;
      _modelCtrl.text = s.model;
      _models = [];
    });
  }

  Future<void> _fetchModels(LlmProvider provider) async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) return;
    setState(() => _loading = true);
    // Anahtari da kaydet ki sonraki acilista hazir olsun.
    ref.read(agentProvider.notifier).saveSettings(apiKey: key);
    final client = LlmClient.create(
      provider: provider,
      apiKey: key,
      model: _modelCtrl.text,
    );
    final models = await client.listModels();
    if (!mounted) return;
    setState(() {
      _models = models;
      _loading = false;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(
      content: Text(models.isEmpty
          ? 'Model bulunamadi (anahtar yanlis olabilir).'
          : '${models.length} model bulundu.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentProvider);
    final notifier = ref.read(agentProvider.notifier);
    final voice = ref.watch(voiceProvider);
    final vc = ref.read(voiceProvider.notifier);
    final provider = state.provider;
    final currentModel =
        _models.contains(_modelCtrl.text) ? _modelCtrl.text : null;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: const Text('Ayarlar', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Model saglayici',
                style: TextStyle(color: Color(0xFF9E9CB8))),
            DropdownButton<LlmProvider>(
              value: provider,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E1E2E),
              style: const TextStyle(color: Colors.white),
              items: LlmProvider.values
                  .map((p) =>
                      DropdownMenuItem(value: p, child: Text(p.label)))
                  .toList(),
              onChanged: (p) {
                if (p != null) _onProviderChanged(p);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _keyCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: '${provider.label} API Anahtari',
                hintText: provider.keyHint,
              ),
              obscureText: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            // Anahtar girilince "modelleri getir" aktif olur.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_download, size: 18),
                    label: Text(_loading ? 'Getiriliyor...' : 'Modelleri getir'),
                    onPressed: (_keyCtrl.text.trim().isEmpty || _loading)
                        ? null
                        : () => _fetchModels(provider),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_models.isNotEmpty) ...[
              const Text('Model sec',
                  style: TextStyle(color: Color(0xFF9E9CB8))),
              DropdownButton<String>(
                value: currentModel,
                isExpanded: true,
                hint: const Text('Listeden sec',
                    style: TextStyle(color: Color(0xFF6E6C8A))),
                dropdownColor: const Color(0xFF1E1E2E),
                style: const TextStyle(color: Colors.white),
                items: _models
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (m) {
                  if (m != null) setState(() => _modelCtrl.text = m);
                },
              ),
            ],
            TextField(
              controller: _modelCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Model (elle de yazabilirsin)',
                hintText: provider.defaultModel,
              ),
            ),
            if (provider == LlmProvider.gemini)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Google arama (sunucu tarafi)',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text(
                    'Cevaplari Google\'in gercek zamanli aramasiyla destekler.',
                    style: TextStyle(color: Color(0xFF9E9CB8), fontSize: 12)),
                value: state.settings?.googleSearch ?? false,
                activeColor: const Color(0xFF6C5CE7),
                onChanged: (v) => notifier.saveSettings(googleSearch: v),
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
                style: const TextStyle(color: Colors.white, fontSize: 13)),
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
                onPressed: () => vc.speak(
                    'Merhaba, ben senin ajaninim. Bu bir hiz denemesi.'),
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
        FilledButton(
          onPressed: () {
            notifier.saveSettings(
                apiKey: _keyCtrl.text, model: _modelCtrl.text);
            Navigator.pop(context);
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
