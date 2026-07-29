import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Basit kalici log. Native cokme (SIGSEGV) Dart try/catch ile yakalanamaz;
/// bu yuzden her satir SENKRON + flush ile dosyaya yazilir. Uygulama cokup
/// yeniden acildiginda son satir, nerede coktugunu gosterir.
class AppLog {
  static File? _file;
  static final List<String> _mem = [];
  static const _max = 500;

  static Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/ajan_log.txt');
      if (await _file!.exists()) {
        final existing = await _file!.readAsLines();
        _mem.addAll(existing.length > _max
            ? existing.sublist(existing.length - _max)
            : existing);
      }
      add('i', '--- uygulama basladi ---');
    } catch (_) {}
  }

  static void add(String level, String msg) {
    final line =
        '${DateTime.now().toIso8601String().substring(11, 19)} [$level] $msg';
    _mem.add(line);
    if (_mem.length > _max) _mem.removeRange(0, _mem.length - _max);
    if (kDebugMode) debugPrint(line);
    // Senkron + flush: native cokme oncesi diske yazilsin.
    try {
      _file?.writeAsStringSync('$line\n',
          mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  static void i(String m) => add('i', m);
  static void e(String m) => add('E', m);

  static List<String> lines() => List.of(_mem);

  static Future<void> clear() async {
    _mem.clear();
    try {
      if (_file != null && await _file!.exists()) {
        await _file!.writeAsString('');
      }
    } catch (_) {}
  }
}
