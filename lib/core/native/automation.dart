import 'package:flutter/services.dart';

/// Ekran otomasyonu ve overlay kopruleri (MainActivity ile eslesir).
class Automation {
  static const _ch = MethodChannel('ajan/native');

  static Future<String> readScreen() async =>
      await _ch.invokeMethod<String>('screenRead') ?? '(bos)';

  static Future<String> tap(String text) async =>
      await _ch.invokeMethod<String>('screenTap', {'text': text}) ?? 'ok';

  static Future<String> type(String text) async =>
      await _ch.invokeMethod<String>('screenType', {'text': text}) ?? 'ok';

  static Future<String> scroll(String direction) async =>
      await _ch.invokeMethod<String>('screenScroll', {'direction': direction}) ?? 'ok';

  static Future<String> global(String action) async =>
      await _ch.invokeMethod<String>('screenGlobal', {'action': action}) ?? 'ok';

  static Future<bool> isAccessibilityOn() async =>
      await _ch.invokeMethod<bool>('isAccessibilityOn') ?? false;

  static Future<void> openAccessibilitySettings() async =>
      await _ch.invokeMethod('openAccessibilitySettings');

  static Future<bool> hasOverlayPermission() async =>
      await _ch.invokeMethod<bool>('hasOverlayPermission') ?? false;

  static Future<void> requestOverlayPermission() async =>
      await _ch.invokeMethod('requestOverlayPermission');

  static Future<String> overlayStart() async =>
      await _ch.invokeMethod<String>('overlayStart') ?? 'ok';

  static Future<String> overlayStop() async =>
      await _ch.invokeMethod<String>('overlayStop') ?? 'ok';
}
