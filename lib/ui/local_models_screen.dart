import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/local/gemma_engine.dart';
import '../core/local/model_catalog.dart';
import '../providers/local_model_provider.dart';
import 'theme.dart';

/// Yerel (offline) modelleri listeler, indirir, siler, aktif secer.
class LocalModelsScreen extends ConsumerWidget {
  const LocalModelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(localModelProvider);
    final ctrl = ref.read(localModelProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Yerel modeller'),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.brand),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const _GemmaSection(),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(
              'DIGER MODELLER (GGUF)',
              style: TextStyle(
                  color: AppColors.primaryLight,
                  fontSize: 12,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'Bu GGUF modeller su an sadece indirilir/yonetilir (motoru henuz '
              'baglanmadi). Offline calistirma icin yukaridaki flutter_gemma '
              'modelini kullan.',
              style: TextStyle(color: AppColors.textFaint, fontSize: 12),
            ),
          ),
          ...kModelCatalog.map((m) => _ModelCard(
                model: m,
                state: state,
                ctrl: ctrl,
              )),
        ],
      ),
    );
  }
}

/// flutter_gemma (MediaPipe) offline motoru: indir & kur.
class _GemmaSection extends StatefulWidget {
  const _GemmaSection();
  @override
  State<_GemmaSection> createState() => _GemmaSectionState();
}

class _GemmaSectionState extends State<_GemmaSection> {
  bool _installed = false;
  bool _busy = false;
  double _progress = 0;
  String _error = '';
  final _urlCtrl = TextEditingController(text: GemmaEngine.recommendedUrl);

  @override
  void initState() {
    super.initState();
    gemmaEngine.isInstalled().then((v) {
      if (mounted) setState(() => _installed = v);
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _progress = 0;
      _error = '';
    });
    final err = await gemmaEngine.install(
      url: _urlCtrl.text,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _installed = err == null;
      _error = err ?? '';
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err == null
          ? 'Offline model kuruldu. Artik internetsiz de sohbet edebilirsin.'
          : 'Kurulum basarisiz. Ayrinti asagida.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: _installed
            ? Border.all(color: AppColors.success, width: 1.2)
            : Border.all(color: AppColors.primary, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Offline motor — Gemma 3 1B (GPU)',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
              'Internetsiz calisan asil model. GATED model icin: (1) Ayarlar\'da '
              'HuggingFace token gir, (2) modelin HF sayfasinda lisansi KABUL '
              'et. Aksi halde indirme 403 verir. Kendi .task/.litertlm URL\'ni '
              'de yapistirabilirsin.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 10),
          if (_busy) ...[
            LinearProgressIndicator(
              value: _progress == 0 ? null : _progress,
              color: AppColors.primary,
              backgroundColor: AppColors.surface,
            ),
            const SizedBox(height: 6),
            Text('%${(_progress * 100).toStringAsFixed(0)} indiriliyor...',
                style: const TextStyle(
                    color: AppColors.textFaint, fontSize: 12)),
          ] else if (_installed)
            Row(
              children: const [
                Icon(Icons.check_circle, color: AppColors.success, size: 18),
                SizedBox(width: 6),
                Text('Kurulu — offline hazir',
                    style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600)),
              ],
            )
          else ...[
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Model URL (.task / .litertlm)',
                labelStyle: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Offline modeli indir & kur'),
                onPressed: _install,
              ),
            ),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0x33E74C3C),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText('Hata: $_error',
                  style: const TextStyle(
                      color: Color(0xFFFFB4A9), fontSize: 11.5)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  final LocalModelInfo model;
  final LocalModelState state;
  final LocalModelController ctrl;
  const _ModelCard(
      {required this.model, required this.state, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final downloading = state.progress.containsKey(model.id);
    final progress = state.progress[model.id] ?? 0.0;
    final downloaded = state.downloaded.contains(model.fileName);
    final active = state.activeFile == model.fileName;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: active
            ? Border.all(color: AppColors.primary, width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(model.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
              Text('${(model.sizeMb / 1024).toStringAsFixed(1)} GB',
                  style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(model.description,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 10),
          if (downloading) ...[
            LinearProgressIndicator(
              value: progress == 0 ? null : progress,
              color: AppColors.primary,
              backgroundColor: AppColors.surface,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('%${(progress * 100).toStringAsFixed(0)} indiriliyor',
                    style: const TextStyle(
                        color: AppColors.textFaint, fontSize: 12)),
                const Spacer(),
                TextButton(
                  onPressed: () => ctrl.cancel(model.id),
                  child: const Text('Iptal',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ] else if (downloaded) ...[
            Row(
              children: [
                if (active)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text('Aktif',
                        style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600)),
                  )
                else
                  OutlinedButton(
                    onPressed: () => ctrl.setActive(model.fileName),
                    child: const Text('Aktif yap'),
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.redAccent),
                  onPressed: () => ctrl.delete(model),
                ),
              ],
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Indir'),
                onPressed: () => ctrl.download(model),
              ),
            ),
        ],
      ),
    );
  }
}
