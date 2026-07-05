import '../native/native_tools.dart';
import 'tool.dart';

/// Gecikmeli/zamanli bildirim planlar. "5 dakika sonra hatirlat" gibi
/// istekler icin BUNU kullan; run_shell + sleep KULLANMA (o bloklar/timeout olur).
class ScheduleNotificationTool extends Tool {
  @override
  String get name => 'schedule_notification';

  @override
  String get description =>
      'Belirtilen sure (saniye) sonra bir bildirim/hatirlatma planlar. '
      'Ornek: "5 dakika sonra hatirlat" -> delay_seconds=300. '
      'Telefon kapali/uykuda olsa bile tam zamaninda calisir. '
      'Gecikmeli hatirlatmalar icin HER ZAMAN bunu kullan, sleep KULLANMA.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'delay_seconds': {
            'type': 'integer',
            'description': 'Kac saniye sonra bildirim gelsin (5 dk = 300).',
          },
          'title': {'type': 'string', 'description': 'Bildirim basligi.'},
          'body': {'type': 'string', 'description': 'Bildirim metni.'},
        },
        'required': ['delay_seconds', 'title', 'body'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) {
    final delay = (args['delay_seconds'] is int)
        ? args['delay_seconds'] as int
        : int.tryParse('${args['delay_seconds']}') ?? 60;
    return NativeTools.scheduleNotification(
      delay,
      (args['title'] ?? 'Hatirlatma').toString(),
      (args['body'] ?? '').toString(),
    );
  }
}
