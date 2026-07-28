/// Bir alarm. Gunler Calendar.DAY_OF_WEEK ile uyumludur:
/// 1=Pazar, 2=Pazartesi, ... 7=Cumartesi. Bos liste = tek seferlik.
class Alarm {
  final int id;
  int hour;
  int minute;
  String label;
  List<int> days;
  bool enabled;
  bool vibrate;
  bool sound;

  Alarm({
    required this.id,
    required this.hour,
    required this.minute,
    this.label = '',
    this.days = const [],
    this.enabled = true,
    this.vibrate = true,
    this.sound = true,
  });

  bool get isRepeating => days.isNotEmpty;

  String get timeText =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  factory Alarm.fromJson(Map<String, dynamic> j) => Alarm(
        id: (j['id'] as num).toInt(),
        hour: (j['hour'] as num).toInt(),
        minute: (j['minute'] as num).toInt(),
        label: (j['label'] ?? '').toString(),
        days: ((j['days'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        enabled: j['enabled'] != false,
        vibrate: j['vibrate'] != false,
        sound: j['sound'] != false,
      );
}
