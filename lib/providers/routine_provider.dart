import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/agent/headless_agent.dart';
import '../core/native/native_tools.dart';
import '../core/store/routine_store.dart';
import '../models/routine.dart';

/// Rutinleri (zamanlanmis/tekrar eden otonom gorevler) yonetir ve zamani
/// gelenleri arka planda calistirir.
///
/// Uygulama sureci canli oldugu surece (kalici on plan servisi sayesinde
/// genelde canlidir) periyodik olarak vadesi gelen rutinleri kontrol eder.
/// Ayrica en yakin rutin icin native exact-alarm ile uygulamayi uyandirir.
class RoutineController extends StateNotifier<List<Routine>> {
  RoutineController() : super([]) {
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  final RoutineStore _store = RoutineStore();
  static const _uuid = Uuid();
  Timer? _ticker;
  bool _running = false;

  /// Araclarin (create_routine vb.) disaridan okuyabilmesi icin.
  List<Routine> get routines => state;

  Future<void> _load() async {
    state = await _store.loadAll();
    _scheduleNextWake();
    _tick(); // acilista vadesi gecmisleri hemen calistir
  }

  Future<void> _persist() async {
    await _store.saveAll(state);
    state = [...state];
  }

  Future<Routine> add({
    required String name,
    required String prompt,
    required int intervalMinutes,
    required DateTime firstRun,
  }) async {
    final r = Routine(
      id: _uuid.v4(),
      name: name,
      prompt: prompt,
      intervalMinutes: intervalMinutes,
      nextRun: firstRun,
    );
    state = [...state, r];
    await _persist();
    _scheduleNextWake();
    return r;
  }

  Future<void> remove(String id) async {
    state = state.where((r) => r.id != id).toList();
    await _persist();
    _scheduleNextWake();
  }

  Future<void> toggle(String id, bool enabled) async {
    for (final r in state) {
      if (r.id == id) r.enabled = enabled;
    }
    await _persist();
    _scheduleNextWake();
  }

  /// Bir rutini hemen calistirir (test icin).
  Future<void> runNow(String id) async {
    final r = state.firstWhere((e) => e.id == id, orElse: () => _none);
    if (r.id.isEmpty) return;
    await _execute(r);
  }

  static final Routine _none =
      Routine(id: '', name: '', prompt: '', intervalMinutes: 0, nextRun: DateTime.now());

  DateTime? get _earliestNext {
    final due = state.where((r) => r.enabled).map((r) => r.nextRun).toList();
    if (due.isEmpty) return null;
    due.sort();
    return due.first;
  }

  void _scheduleNextWake() {
    final next = _earliestNext;
    if (next == null) return;
    final ms = next.difference(DateTime.now()).inMilliseconds;
    // Cok yakinsa ticker zaten yakalar; ileri tarihliyse cihazi uyandir.
    if (ms > 60 * 1000) {
      NativeTools.scheduleWake(ms).catchError((_) => 'err');
    }
  }

  Future<void> _tick() async {
    if (_running) return;
    final now = DateTime.now();
    final due = state
        .where((r) => r.enabled && !r.nextRun.isAfter(now))
        .toList();
    if (due.isEmpty) return;
    _running = true;
    try {
      for (final r in due) {
        await _execute(r);
      }
    } finally {
      _running = false;
      _scheduleNextWake();
    }
  }

  Future<void> _execute(Routine r) async {
    await NativeTools.startAgentTask();
    try {
      final result = await runAgentOnce(r.prompt);
      r.lastRun = DateTime.now();
      r.lastResult = result;
      await NativeTools.notify(r.name, result);
    } catch (e) {
      r.lastRun = DateTime.now();
      r.lastResult = 'Hata: $e';
      if (kDebugMode) debugPrint('routine error: $e');
    } finally {
      await NativeTools.stopAgentTask();
      // Sonraki calisma zamanini ayarla / tek seferligi kapat.
      if (r.isRecurring) {
        var next = r.nextRun.add(Duration(minutes: r.intervalMinutes));
        final now = DateTime.now();
        while (!next.isAfter(now)) {
          next = next.add(Duration(minutes: r.intervalMinutes));
        }
        r.nextRun = next;
      } else {
        r.enabled = false;
      }
      await _persist();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

/// Tek ortak ornek: hem UI (Riverpod) hem de araclar (create_routine vb.) ayni
/// zamanlayiciyi paylassin.
final RoutineController routineController = RoutineController();

final routineProvider =
    StateNotifierProvider<RoutineController, List<Routine>>(
        (ref) => routineController);
