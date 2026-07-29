import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yerel model dosyalarini yonetir: indir (ilerlemeli), listele, sil, aktif sec.
class LocalModelStore {
  static const _kActive = 'local_model_active';

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/models');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<String> pathFor(String fileName) async =>
      '${(await _dir()).path}/$fileName';

  Future<bool> isDownloaded(String fileName) async =>
      File(await pathFor(fileName)).exists();

  Future<int> sizeOf(String fileName) async {
    final f = File(await pathFor(fileName));
    return await f.exists() ? await f.length() : 0;
  }

  Future<void> delete(String fileName) async {
    final f = File(await pathFor(fileName));
    if (await f.exists()) await f.delete();
    final active = await activeFile();
    if (active == fileName) await setActive('');
  }

  Future<String> activeFile() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kActive) ?? '';
  }

  Future<void> setActive(String fileName) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kActive, fileName);
  }

  /// Aktif modelin tam dosya yolu; yoksa bos string.
  Future<String> activeModelPath() async {
    final f = await activeFile();
    if (f.isEmpty) return '';
    final path = await pathFor(f);
    return await File(path).exists() ? path : '';
  }

  /// Modeli indirir. [onProgress] 0..1 arasi ilerleme. Iptal icin [cancel]
  /// tamamlandiginda true doner.
  Future<bool> download(
    String url,
    String fileName, {
    required void Function(double progress) onProgress,
    required bool Function() cancelled,
  }) async {
    final client = http.Client();
    final tmpPath = '${await pathFor(fileName)}.part';
    final tmp = File(tmpPath);
    IOSink? sink;
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await client.send(req);
      if (res.statusCode != 200) {
        return false;
      }
      final total = res.contentLength ?? 0;
      var received = 0;
      sink = tmp.openWrite();
      await for (final chunk in res.stream) {
        if (cancelled()) {
          await sink.close();
          if (await tmp.exists()) await tmp.delete();
          return false;
        }
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress(received / total);
      }
      await sink.close();
      sink = null;
      // Tamam: .part -> gercek dosya
      await tmp.rename(await pathFor(fileName));
      onProgress(1.0);
      return true;
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
      return false;
    } finally {
      client.close();
    }
  }
}
