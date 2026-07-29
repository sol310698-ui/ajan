import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              'Offline modeller (int4). WiFi ile indir, "Aktif yap".\n'
              'Not: Calistirma motoru bu surumde bundlanmadi (llama.cpp APK\'yi '
              'cok buyutuyordu). Indirme/yonetim calisir; motor daha hafif bir '
              'cozumle yakinda baglanacak.',
              style: TextStyle(color: AppColors.textFaint, fontSize: 12.5),
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
