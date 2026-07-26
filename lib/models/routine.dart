/// Zamanlanmis / tekrar eden otonom gorev.
///
/// Ornek: "her sabah 08:00'de hava durumunu bildir" -> intervalMinutes=1440,
/// nextRun = yarin 08:00. Tek seferlik ("yarin 15:00'te hatirlat") icin
/// intervalMinutes=0.
class Routine {
  final String id;
  String name;
  String prompt;
  int intervalMinutes; // 0 = tek seferlik
  DateTime nextRun;
  bool enabled;
  DateTime? lastRun;
  String lastResult;

  Routine({
    required this.id,
    required this.name,
    required this.prompt,
    required this.intervalMinutes,
    required this.nextRun,
    this.enabled = true,
    this.lastRun,
    this.lastResult = '',
  });

  bool get isRecurring => intervalMinutes > 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'prompt': prompt,
        'intervalMinutes': intervalMinutes,
        'nextRun': nextRun.toIso8601String(),
        'enabled': enabled,
        'lastRun': lastRun?.toIso8601String(),
        'lastResult': lastResult,
      };

  factory Routine.fromJson(Map<String, dynamic> j) => Routine(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? 'Rutin').toString(),
        prompt: (j['prompt'] ?? '').toString(),
        intervalMinutes: (j['intervalMinutes'] is int)
            ? j['intervalMinutes'] as int
            : int.tryParse('${j['intervalMinutes']}') ?? 0,
        nextRun: DateTime.tryParse((j['nextRun'] ?? '').toString()) ??
            DateTime.now(),
        enabled: j['enabled'] != false,
        lastRun: j['lastRun'] == null
            ? null
            : DateTime.tryParse(j['lastRun'].toString()),
        lastResult: (j['lastResult'] ?? '').toString(),
      );
}
