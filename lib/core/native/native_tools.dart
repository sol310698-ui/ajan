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

  /// [delaySeconds] saniye sonra bir bildirim planlar (AlarmManager).
  static Future<String> scheduleNotification(
      int delaySeconds, String title, String body) async {
    final r = await _ch.invokeMethod<String>('scheduleNotification', {
      'delaySeconds': delaySeconds,
      'title': title,
      'body': body,
    });
    return r ?? 'ok';
  }
}
