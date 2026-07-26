import '../../providers/routine_provider.dart';
import 'tool.dart';

/// Tekrar eden veya belirli bir saatte kendiliginden calisacak otonom gorev
/// olusturur.
class CreateRoutineTool extends Tool {
  @override
  String get name => 'create_routine';

  @override
  String get description =>
      'Kendiliginden (sen istemeden) calisacak otonom bir gorev kurar. '
      'Ornek: "her sabah 08:00 hava durumunu bildir", "her 2 saatte pili '
      'kontrol et", "yarin 15:00 toplantiyi hatirlat". Gorev zamani gelince '
      'ajan gorevi calistirir ve sonucu bildirim olarak gonderir. '
      'Tekrar eden gorevler icin interval_minutes ver (gunluk=1440, saatlik=60). '
      'Tek seferlik icin interval_minutes=0 ver. first_run_iso ilk calisma '
      'zamanidir (ISO-8601, ornek 2026-07-27T08:00:00); verilmezse tekrar '
      'edenlerde simdi+interval alinir.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Kisa gorev adi (bildirim basligi olur).',
          },
          'prompt': {
            'type': 'string',
            'description': 'Gorev zamani gelince ajana verilecek talimat. '
                'Ornek: "Istanbul hava durumunu ozetle ve bana bildir".',
          },
          'interval_minutes': {
            'type': 'integer',
            'description': 'Tekrar araligi (dakika). Gunluk=1440, saatlik=60, '
                'tek seferlik=0.',
          },
          'first_run_iso': {
            'type': 'string',
            'description': 'Ilk calisma zamani (ISO-8601). Opsiyonel.',
          },
        },
        'required': ['name', 'prompt', 'interval_minutes'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final name = (args['name'] ?? 'Rutin').toString();
    final prompt = (args['prompt'] ?? '').toString();
    if (prompt.trim().isEmpty) return 'HATA: prompt bos olamaz.';
    final interval = (args['interval_minutes'] is int)
        ? args['interval_minutes'] as int
        : int.tryParse('${args['interval_minutes']}') ?? 0;

    DateTime? first =
        DateTime.tryParse((args['first_run_iso'] ?? '').toString());
    if (first == null) {
      first = interval > 0
          ? DateTime.now().add(Duration(minutes: interval))
          : DateTime.now().add(const Duration(minutes: 1));
    }

    final r = await routineController.add(
      name: name,
      prompt: prompt,
      intervalMinutes: interval,
      firstRun: first,
    );
    final tekrar = interval > 0
        ? 'her $interval dakikada bir'
        : 'tek seferlik';
    return 'Rutin kuruldu: "${r.name}" ($tekrar), ilk calisma: '
        '${first.toString().substring(0, 16)}.';
  }
}

/// Kayitli rutinleri listeler.
class ListRoutinesTool extends Tool {
  @override
  String get name => 'list_routines';
  @override
  String get description => 'Kayitli otonom gorevleri (rutinleri) listeler.';
  @override
  Map<String, dynamic> get parameters =>
      {'type': 'object', 'properties': {}};
  @override
  Future<String> run(Map<String, dynamic> args) async {
    final list = routineController.routines;
    if (list.isEmpty) return 'Kayitli rutin yok.';
    return list.map((r) {
      final durum = r.enabled ? 'aktif' : 'kapali';
      final tekrar =
          r.isRecurring ? 'her ${r.intervalMinutes} dk' : 'tek seferlik';
      return '#${r.id.substring(0, 6)} ${r.name} [$durum, $tekrar] '
          'sonraki: ${r.nextRun.toString().substring(0, 16)}';
    }).join('\n');
  }
}

/// Bir rutini iptal eder / siler.
class CancelRoutineTool extends Tool {
  @override
  String get name => 'cancel_routine';
  @override
  String get description =>
      'Bir rutini siler. list_routines ciktisindaki id (ilk 6 karakter de '
      'yeterli) veya rutin adi verilebilir.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'id_or_name': {
            'type': 'string',
            'description': 'Silinecek rutinin id veya adi.',
          },
        },
        'required': ['id_or_name'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) async {
    final q = (args['id_or_name'] ?? '').toString().trim().toLowerCase();
    if (q.isEmpty) return 'HATA: id_or_name gerekli.';
    final match = routineController.routines.where((r) =>
        r.id.toLowerCase().startsWith(q) ||
        r.name.toLowerCase() == q ||
        r.name.toLowerCase().contains(q));
    if (match.isEmpty) return 'Rutin bulunamadi: $q';
    final ids = match.map((r) => r.id).toList();
    for (final id in ids) {
      await routineController.remove(id);
    }
    return '${ids.length} rutin silindi.';
  }
}
