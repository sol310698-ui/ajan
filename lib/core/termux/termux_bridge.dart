import 'package:flutter/services.dart';

/// Termux ile kopru. Native tarafta com.termux.RUN_COMMAND intent'i ile
/// komut gonderir, cikti bir dosyaya yazilir ve geri okunur.
///
/// Gereksinimler (kullanici bir kez yapar):
///  1. Termux ve Termux:API kurulu (F-Droid).
///  2. ~/.termux/termux.properties icinde: allow-external-apps=true
///  3. `termux-setup-storage` calistirilmis olmali.
class TermuxBridge {
  static const _ch = MethodChannel('ajan/native');

  /// Bir shell komutu calistirir ve stdout+stderr dondurur.
  /// [timeoutSec] sure asiminda islem iptal edilir.
  static Future<String> run(String command, {int timeoutSec = 60}) async {
    try {
      final result = await _ch.invokeMethod<String>('termuxRun', {
        'command': command,
        'timeoutSec': timeoutSec,
      });
      return result ?? '(bos cikti)';
    } on PlatformException catch (e) {
      return 'HATA (termux): ${e.message}';
    }
  }
}
