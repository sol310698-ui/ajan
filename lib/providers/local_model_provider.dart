import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/local/local_model_store.dart';
import '../core/local/model_catalog.dart';

class LocalModelState {
  final Set<String> downloaded; // indirilmis dosya adlari
  final Map<String, double> progress; // id -> 0..1 (indiriliyor)
  final String activeFile;

  const LocalModelState({
    this.downloaded = const {},
    this.progress = const {},
    this.activeFile = '',
  });

  LocalModelState copyWith({
    Set<String>? downloaded,
    Map<String, double>? progress,
    String? activeFile,
  }) =>
      LocalModelState(
        downloaded: downloaded ?? this.downloaded,
        progress: progress ?? this.progress,
        activeFile: activeFile ?? this.activeFile,
      );
}

class LocalModelController extends StateNotifier<LocalModelState> {
  LocalModelController() : super(const LocalModelState()) {
    refresh();
  }

  final LocalModelStore _store = LocalModelStore();
  final Map<String, bool> _cancel = {};

  Future<void> refresh() async {
    final dl = <String>{};
    for (final m in kModelCatalog) {
      if (await _store.isDownloaded(m.fileName)) dl.add(m.fileName);
    }
    state = state.copyWith(
      downloaded: dl,
      activeFile: await _store.activeFile(),
    );
  }

  bool isDownloading(String id) => state.progress.containsKey(id);

  Future<void> download(LocalModelInfo m) async {
    if (isDownloading(m.id)) return;
    _cancel[m.id] = false;
    state = state.copyWith(progress: {...state.progress, m.id: 0.0});

    final ok = await _store.download(
      m.url,
      m.fileName,
      onProgress: (p) {
        state = state.copyWith(progress: {...state.progress, m.id: p});
      },
      cancelled: () => _cancel[m.id] == true,
    );

    final prog = {...state.progress}..remove(m.id);
    state = state.copyWith(progress: prog);
    _cancel.remove(m.id);
    if (ok) {
      final dl = {...state.downloaded, m.fileName};
      // Ilk indirilen otomatik aktif olsun.
      final active =
          state.activeFile.isEmpty ? m.fileName : state.activeFile;
      if (active != state.activeFile) await _store.setActive(active);
      state = state.copyWith(downloaded: dl, activeFile: active);
    }
  }

  void cancel(String id) => _cancel[id] = true;

  Future<void> delete(LocalModelInfo m) async {
    await _store.delete(m.fileName);
    await refresh();
  }

  Future<void> setActive(String fileName) async {
    await _store.setActive(fileName);
    state = state.copyWith(activeFile: fileName);
  }
}

final localModelProvider =
    StateNotifierProvider<LocalModelController, LocalModelState>(
        (ref) => LocalModelController());
