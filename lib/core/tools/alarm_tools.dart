import 'dart:convert';

import '../native/native_tools.dart';
import 'tool.dart';

/// Model gunleri (Calendar.DAY_OF_WEEK: 1=Pazar ... 7=Cumartesi).
List<int> _daysFor(String repeat) {
  switch (repeat.toLowerCase().trim()) {
    case 'daily':
    case 'hergun':
    case 'her gun':
      return [1, 2, 3, 4, 5, 6, 7];
    case 'weekdays':
    case 'hafta ici':
    case 'haftaici':
      return [2, 3, 4, 5, 6];
    case 'weekends':
    case 'hafta sonu':
    case 'haftasonu':
      return [1, 7];
    default:
      return const [];
  }
}

/// Alarm kurar (native alarm sistemine). "Her sabah 7de alarm kur" gibi
/// istekler icin.
class SetAlarmTool extends Tool {
  @override
  String get name => 'set_alarm';

  @override
  String get description =>
      'Cihazda gercek bir alarm kurar (uygulama kapali olsa bile calar). '
      'Saat ve dakika 24 saat formatinda. repeat: "once" (tek sefer), '
      '"daily" (her gun), "weekdays" (hafta ici), "weekends" (hafta sonu). '
      'Hatirlatma degil, calan ALARM istenince bunu kullan.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'hour': {'type': 'integer', 'description': 'Saat (0-23).'},
          'minute': {'type': 'integer', 'description': 'Dakika (0-59).'},
          'label': {'type': 'string', 'description': 'Alarm etiketi (opsiyonel).'},
          'repeat': {
            'type': 'string',
            'description': 'once | daily | weekdays | weekends',
          },
        },
        'required': ['hour', 'minute'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final hour = (args['hour'] is int)
        ? args['hour'] as int
        : int.tryParse('${args['hour']}') ?? 8;
    final minute = (args['minute'] is int)
        ? args['minute'] as int
        : int.tryParse('${args['minute']}') ?? 0;
    final days = _daysFor((args['repeat'] ?? 'once').toString());
    await NativeTools.alarmsAdd(
      hour: hour.clamp(0, 23),
      minute: minute.clamp(0, 59),
      label: (args['label'] ?? '').toString(),
      days: days,
      vibrate: true,
      sound: true,
    );
    final tekrar = days.isEmpty ? 'tek sefer' : (args['repeat'] ?? '').toString();
    return 'Alarm kuruldu: ${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')} ($tekrar).';
  }
}

/// Kayitli alarmlari listeler.
class ListAlarmsTool extends Tool {
  @override
  String get name => 'list_alarms';
  @override
  String get description => 'Kayitli alarmlari listeler.';
  @override
  Map<String, dynamic> get parameters =>
      {'type': 'object', 'properties': {}};
  @override
  Future<String> run(Map<String, dynamic> args) async {
    final raw = await NativeTools.alarmsGet();
    try {
      final list = jsonDecode(raw) as List;
      if (list.isEmpty) return 'Kayitli alarm yok.';
      return list.map((e) {
        final o = Map<String, dynamic>.from(e);
        final h = (o['hour'] as num).toInt().toString().padLeft(2, '0');
        final m = (o['minute'] as num).toInt().toString().padLeft(2, '0');
        final on = o['enabled'] != false ? 'acik' : 'kapali';
        final days = (o['days'] as List?) ?? const [];
        final tekrar = days.isEmpty ? 'tek sefer' : 'tekrarli';
        return 'id=${o['id']} $h:$m [$on, $tekrar] ${o['label'] ?? ''}';
      }).join('\n');
    } catch (_) {
      return 'Alarm listesi okunamadi.';
    }
  }
}

/// Bir alarmi siler.
class DeleteAlarmTool extends Tool {
  @override
  String get name => 'delete_alarm';
  @override
  String get description =>
      'Bir alarmi siler. list_alarms ciktisindaki id verilir.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'id': {'type': 'integer', 'description': 'Silinecek alarmin id degeri.'},
        },
        'required': ['id'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) async {
    final id = (args['id'] is int)
        ? args['id'] as int
        : int.tryParse('${args['id']}') ?? -1;
    if (id < 0) return 'HATA: gecerli id gerekli.';
    await NativeTools.alarmsDelete(id);
    return 'Alarm silindi (id=$id).';
  }
}
