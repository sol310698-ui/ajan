import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/routine.dart';

/// Rutinleri (zamanlanmis otonom gorevler) kalici saklar.
class RoutineStore {
  static const _key = 'routines_v1';

  Future<List<Routine>> loadAll() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Routine.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<Routine> routines) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _key, jsonEncode(routines.map((r) => r.toJson()).toList()));
  }
}
