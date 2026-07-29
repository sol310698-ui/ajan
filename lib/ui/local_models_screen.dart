import 'package:flutter/material.dart';

import '../core/local/gemma_engine.dart';
import 'theme.dart';

/// Cihaz-ici (offline) modeller: HuggingFace token ile indirilebilen, gercekten
/// CALISAN (flutter_gemma/LiteRT) modelleri listeler; sec, indir, kullan.
class LocalModelsScreen extends StatefulWidget {
  const LocalModelsScreen({super.key});
  @override
  State<LocalModelsScreen> createState() => _LocalModelsScreenState();
}

class _LocalModelsScreenState extends State<LocalModelsScreen> {
  List<LiteRtModel> _models = [];
  bool _loading = false;
  String _error = '';
  String _active = '';
  final Map<String, double> _progress = {}; // url -> 0..1

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _active = await gemmaEngine.activeName();
    if (mounted) setState(() {});
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    final list = await gemmaEngine.listDownloadable();
    if (!mounted) return;
    setState(() {
      _models = list;
      _loading = false;
      if (list.isEmpty) {
        _error = 'Model listesi bos geldi. Ayarlar\'da HuggingFace token '
            'girili mi? Token gecerli/lisans kabul edilmis olmali.';
      }
    });
  }

  Future<void> _install(LiteRtModel m) async {
    setState(() => _progress[m.url] = 0);
    final err = await gemmaEngine.install(
      url: m.url,
      name: m.name,
      onProgress: (p) {
        if (mounted) setState(() => _progress[m.url] = p);
      },
    );
    if (!mounted) return;
    setState(() {
      _progress.remove(m.url);
      if (err == null) {
        _active = m.name;
      } else {
        _error = err;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err == null
          ? '${m.name} kuruldu ve aktif. Offline hazir.'
          : 'Kurulum basarisiz. Ayrinti asagida.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Yerel modeller'),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.brand),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Listeyi yenile',
            onPressed: _loading ? null : _fetch,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Offline (internetsiz) calisan modeller. Indirmek icin Ayarlar\'da '
            'HuggingFace token gir ve modelin HF sayfasinda lisansi kabul et. '
            'Kucuk model = hizli ama basit; buyuk = akilli ama yavas/cok RAM.',
            style: TextStyle(color: AppColors.textFaint, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_models.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Model bulunamadi.',
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Modelleri getir'),
                    onPressed: _fetch,
                  ),
                ],
              ),
            )
          else
            ..._models.map(_card),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0x33E74C3C),
                borderRadius: BorderRadius.circular(10),
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

  Widget _card(LiteRtModel m) {
    final downloading = _progress.containsKey(m.url);
    final progress = _progress[m.url] ?? 0.0;
    final active = _active == m.name;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: active ? Border.all(color: AppColors.success, width: 1.3) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(m.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              if (m.sizeMb > 0)
                Text(
                    m.sizeMb >= 1024
                        ? '${(m.sizeMb / 1024).toStringAsFixed(1)} GB'
                        : '${m.sizeMb} MB',
                    style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(m.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textFaint, fontSize: 11)),
          const SizedBox(height: 10),
          if (downloading) ...[
            LinearProgressIndicator(
              value: progress == 0 ? null : progress,
              color: AppColors.primary,
              backgroundColor: AppColors.surface,
            ),
            const SizedBox(height: 6),
            Text('%${(progress * 100).toStringAsFixed(0)} indiriliyor...',
                style:
                    const TextStyle(color: AppColors.textFaint, fontSize: 12)),
          ] else if (active)
            Row(
              children: const [
                Icon(Icons.check_circle, color: AppColors.success, size: 18),
                SizedBox(width: 6),
                Text('Aktif — offline hazir',
                    style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600)),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Indir & kur (aktif yap)'),
                onPressed: () => _install(m),
              ),
            ),
        ],
      ),
    );
  }
}
