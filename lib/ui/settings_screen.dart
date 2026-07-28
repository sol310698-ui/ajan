import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/agent/llm_client.dart';
import '../core/native/automation.dart';
import '../core/voice/voice_service.dart';
import '../providers/agent_provider.dart';
import 'theme.dart';

/// Ayarlar SAYFASI: saglayici + anahtar + model (anahtar girilince modeller
/// API'den cekilip acilir menude gosterilir) + ses + ekran kontrolu.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
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
    ref.read(agentProvider.notifier).saveSettings(apiKey: key);
    final client =
        LlmClient.create(provider: provider, apiKey: key, model: _modelCtrl.text);
    final models = await client.listModels();
    if (!mounted) return;
    setState(() {
      _models = models;
      _loading = false;
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(models.isEmpty
          ? 'Model bulunamadi (anahtar yanlis olabilir).'
          : '${models.length} model bulundu.'),
    ));
  }

  void _save() {
    ref
        .read(agentProvider.notifier)
        .saveSettings(apiKey: _keyCtrl.text, model: _modelCtrl.text);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Ayarlar kaydedildi.')),
    );
    Navigator.of(context).maybePop();
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                color: AppColors.primaryLight,
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700)),
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentProvider);
    final notifier = ref.read(agentProvider.notifier);
    final voice = ref.watch(voiceProvider);
    final vc = ref.read(voiceProvider.notifier);
    final provider = state.provider;
    final currentModel =
        _models.contains(_modelCtrl.text) ? _modelCtrl.text : null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Ayarlar'),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.brand),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Kaydet',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _sectionTitle('Yapay zeka'),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Model saglayici',
                    style: TextStyle(color: AppColors.textSecondary)),
                DropdownButton<LlmProvider>(
                  value: provider,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AppColors.card,
                  style: const TextStyle(color: AppColors.textPrimary),
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
                  style: const TextStyle(color: AppColors.textPrimary),
                  obscureText: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: '${provider.label} API Anahtari',
                    hintText: provider.keyHint,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_download, size: 18),
                    label:
                        Text(_loading ? 'Getiriliyor...' : 'Modelleri getir'),
                    onPressed: (_keyCtrl.text.trim().isEmpty || _loading)
                        ? null
                        : () => _fetchModels(provider),
                  ),
                ),
                if (_models.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Model sec',
                      style: TextStyle(color: AppColors.textSecondary)),
                  DropdownButton<String>(
                    value: currentModel,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    hint: const Text('Listeden sec',
                        style: TextStyle(color: AppColors.textFaint)),
                    dropdownColor: AppColors.card,
                    style: const TextStyle(color: AppColors.textPrimary),
                    items: _models
                        .map((m) =>
                            DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (m) {
                      if (m != null) setState(() => _modelCtrl.text = m);
                    },
                  ),
                ],
                const SizedBox(height: 4),
                TextField(
                  controller: _modelCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Model (elle de yazabilirsin)',
                    hintText: provider.defaultModel,
                  ),
                ),
                if (provider == LlmProvider.gemini)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Google arama modu (sunucu tarafi)',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 14)),
                      subtitle: const Text(
                          'Acikken Gemini yanitlari Google aramasiyla '
                          'desteklenir; bu modda cihaz araclari devre disidir.',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                      value: state.settings?.googleSearch ?? false,
                      activeColor: AppColors.primary,
                      onChanged: (v) =>
                          notifier.saveSettings(googleSearch: v),
                    ),
                  ),
              ],
            ),
          ),
          _sectionTitle('Ses'),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cevaplari sesli oku',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 14)),
                  value: voice.autoSpeak,
                  activeColor: AppColors.primary,
                  onChanged: (v) => vc.setAutoSpeak(v),
                ),
                Text('Konusma hizi: ${voice.rate.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13)),
                Slider(
                  min: 0.2,
                  max: 1.0,
                  divisions: 16,
                  value: voice.rate.clamp(0.2, 1.0),
                  activeColor: AppColors.primary,
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
              ],
            ),
          ),
          _sectionTitle('Ekran kontrolu'),
          _card(
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.accessibility_new, size: 18),
                    label: const Text('Erisilebilirligi ac'),
                    onPressed: () => Automation.openAccessibilitySettings(),
                  ),
                ),
                const SizedBox(height: 8),
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
        ],
      ),
    );
  }
}
