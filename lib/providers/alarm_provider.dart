import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/native/native_tools.dart';
import '../models/alarm.dart';

/// Alarmlari yonetir. Kaynak dogrulugu NATIVE taraftadir (uygulama kapali
/// olsa bile calmasi, boot sonrasi kurtarma icin). Bu kontrolcu native ile
/// konusur ve donen listeyi UI icin tutar.
class AlarmController extends StateNotifier<List<Alarm>> {
  AlarmController() : super([]) {
    refresh();
  }

  List<Alarm> _parse(String json) {
    try {
      final list = (jsonDecode(json) as List)
          .map((e) => Alarm.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      list.sort((a, b) {
        final am = a.hour * 60 + a.minute;
        final bm = b.hour * 60 + b.minute;
        return am.compareTo(bm);
      });
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> refresh() async {
    state = _parse(await NativeTools.alarmsGet());
  }

  Future<void> add({
    required int hour,
    required int minute,
    String label = '',
    List<int> days = const [],
    bool vibrate = true,
    bool sound = true,
  }) async {
    state = _parse(await NativeTools.alarmsAdd(
      hour: hour,
      minute: minute,
      label: label,
      days: days,
      vibrate: vibrate,
      sound: sound,
    ));
  }

  Future<void> update(Alarm a) async {
    state = _parse(await NativeTools.alarmsUpdate(
      id: a.id,
      hour: a.hour,
      minute: a.minute,
      label: a.label,
      days: a.days,
      vibrate: a.vibrate,
      sound: a.sound,
    ));
  }

  Future<void> remove(int id) async {
    state = _parse(await NativeTools.alarmsDelete(id));
  }

  Future<void> setEnabled(int id, bool enabled) async {
    state = _parse(await NativeTools.alarmsSetEnabled(id, enabled));
  }
}

final alarmProvider =
    StateNotifierProvider<AlarmController, List<Alarm>>(
        (ref) => AlarmController());
