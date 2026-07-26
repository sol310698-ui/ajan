import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Ajanin uzun sureli hafizasi: sohbetler arasi kalici gercekler/tercihler.
///
/// Basit anahtar->deger deposudur (ornek: "isim" -> "Samet",
/// "sehir" -> "Istanbul"). Her sohbete sistem talimatiyla enjekte edilir,
/// boylece ajan kullaniciyi "hatirlar".
class MemoryStore {
  static const _key = 'agent_memory_v1';

  final Map<String, String> _facts = {};
  bool _loaded = false;

  Future<void> _ensure() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _facts
          ..clear()
          ..addAll(m.map((k, v) => MapEntry(k, v.toString())));
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(_facts));
  }

  Future<Map<String, String>> all() async {
    await _ensure();
    return Map<String, String>.from(_facts);
  }

  Future<void> remember(String key, String value) async {
    await _ensure();
    _facts[key.trim()] = value.trim();
    await _persist();
  }

  Future<bool> forget(String key) async {
    await _ensure();
    final removed = _facts.remove(key.trim()) != null;
    if (removed) await _persist();
    return removed;
  }

  Future<void> clear() async {
    await _ensure();
    _facts.clear();
    await _persist();
  }

  /// Sistem talimatina eklenecek ozet metni. Bos ise bos string doner.
  Future<String> asPromptBlock() async {
    await _ensure();
    if (_facts.isEmpty) return '';
    final b = StringBuffer(
        '\n\nKullanici hakkinda hatirladiklarin (uzun sureli hafiza):\n');
    _facts.forEach((k, v) => b.writeln('- $k: $v'));
    b.writeln('Bunlari dogal sekilde kullan; gerektiginde remember araciyla '
        'guncelle.');
    return b.toString();
  }
}

/// Uygulama boyunca tek ornek (araclar ve provider ayni hafizayi paylassin).
final memoryStore = MemoryStore();
