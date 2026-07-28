import 'package:flutter/services.dart';

/// Native Android islemleri icin kopru (Kotlin MainActivity ile eslesir).
class NativeTools {
  static const _ch = MethodChannel('ajan/native');

  static Future<String> openApp(String query) async {
    final r = await _ch.invokeMethod<String>('openApp', {'query': query});
    return r ?? 'ok';
  }

  static Future<String> sendSms(String number, String message) async {
    final r = await _ch.invokeMethod<String>('sendSms', {
      'number': number,
      'message': message,
    });
    return r ?? 'ok';
  }

  static Future<String> getLocation() async {
    final r = await _ch.invokeMethod<String>('getLocation');
    return r ?? 'bilinmiyor';
  }

  static Future<String> notify(String title, String body) async {
    final r = await _ch.invokeMethod<String>('notify', {
      'title': title,
      'body': body,
    });
    return r ?? 'ok';
  }

  static Future<String> scheduleNotification(
      int delaySeconds, String title, String body) async {
    final r = await _ch.invokeMethod<String>('scheduleNotification', {
      'delaySeconds': delaySeconds,
      'title': title,
      'body': body,
    });
    return r ?? 'ok';
  }

  /// Gorev basladiginda cagrilir: CPU'yu uyanik tutar (wake lock).
  static Future<void> startAgentTask() async {
    try {
      await _ch.invokeMethod('startAgentTask');
    } catch (_) {}
  }

  /// Gorev bitince cagrilir: wake lock birakilir (batarya).
  static Future<void> stopAgentTask() async {
    try {
      await _ch.invokeMethod('stopAgentTask');
    } catch (_) {}
  }

  // --- Cihaz araclari (genisletilmis) ---

  static Future<String> clipboardGet() async =>
      await _ch.invokeMethod<String>('clipboardGet') ?? '';

  static Future<String> clipboardSet(String text) async =>
      await _ch.invokeMethod<String>('clipboardSet', {'text': text}) ?? 'ok';

  static Future<String> batteryStatus() async =>
      await _ch.invokeMethod<String>('batteryStatus') ?? 'bilinmiyor';

  static Future<String> deviceInfo() async =>
      await _ch.invokeMethod<String>('deviceInfo') ?? 'bilinmiyor';

  static Future<String> toggleTorch(bool on) async =>
      await _ch.invokeMethod<String>('toggleTorch', {'on': on}) ?? 'ok';

  static Future<String> makeCall(String number) async =>
      await _ch.invokeMethod<String>('makeCall', {'number': number}) ?? 'ok';

  static Future<String> readContacts(String query) async =>
      await _ch.invokeMethod<String>('readContacts', {'query': query}) ?? '';

  static Future<String> readSms(int limit) async =>
      await _ch.invokeMethod<String>('readSms', {'limit': limit}) ?? '';

  static Future<String> addCalendarEvent(
    String title,
    String description,
    int startMillis,
    int endMillis,
  ) async =>
      await _ch.invokeMethod<String>('addCalendarEvent', {
        'title': title,
        'description': description,
        'start': startMillis,
        'end': endMillis,
      }) ??
      'ok';

  static Future<String> listApps() async =>
      await _ch.invokeMethod<String>('listApps') ?? '';

  static Future<String> setVolume(int percent) async =>
      await _ch.invokeMethod<String>('setVolume', {'percent': percent}) ?? 'ok';

  static Future<String> vibrate(int ms) async =>
      await _ch.invokeMethod<String>('vibrate', {'ms': ms}) ?? 'ok';

  static Future<String> openUrl(String url) async =>
      await _ch.invokeMethod<String>('openUrl', {'url': url}) ?? 'ok';

  static Future<String> openSettings(String panel) async =>
      await _ch.invokeMethod<String>('openSettings', {'panel': panel}) ?? 'ok';

  /// Rutin/otonom gorev icin: verilen ms sonra uygulamayi uyandir (exact alarm).
  static Future<String> scheduleWake(int delayMillis) async =>
      await _ch.invokeMethod<String>('scheduleWake', {'delayMillis': delayMillis}) ??
      'ok';

  // --- Alarm/Saat (native kaynak dogrulugu: tum liste JSON doner) ---

  static Future<String> alarmsGet() async =>
      await _ch.invokeMethod<String>('alarmsGet') ?? '[]';

  static Future<String> alarmsAdd({
    required int hour,
    required int minute,
    required String label,
    required List<int> days,
    required bool vibrate,
    required bool sound,
  }) async =>
      await _ch.invokeMethod<String>('alarmsAdd', {
        'hour': hour,
        'minute': minute,
        'label': label,
        'days': days,
        'vibrate': vibrate,
        'sound': sound,
      }) ??
      '[]';

  static Future<String> alarmsUpdate({
    required int id,
    required int hour,
    required int minute,
    required String label,
    required List<int> days,
    required bool vibrate,
    required bool sound,
  }) async =>
      await _ch.invokeMethod<String>('alarmsUpdate', {
        'id': id,
        'hour': hour,
        'minute': minute,
        'label': label,
        'days': days,
        'vibrate': vibrate,
        'sound': sound,
      }) ??
      '[]';

  static Future<String> alarmsDelete(int id) async =>
      await _ch.invokeMethod<String>('alarmsDelete', {'id': id}) ?? '[]';

  static Future<String> alarmsSetEnabled(int id, bool enabled) async =>
      await _ch.invokeMethod<String>(
          'alarmsSetEnabled', {'id': id, 'enabled': enabled}) ??
      '[]';
}
