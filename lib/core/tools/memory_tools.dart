import '../store/memory_store.dart';
import 'tool.dart';

/// Kullanici hakkinda kalici bir bilgi/tercih kaydeder (uzun sureli hafiza).
class RememberTool extends Tool {
  @override
  String get name => 'remember';

  @override
  String get description =>
      'Kullanici hakkinda ILERIDE de gecerli olacak kalici bir bilgiyi/tercihi '
      'hafizaya yaz. Ornek: isim, dogum gunu, sevdigi seyler, calisma saatleri, '
      'ev/is adresi, alismis oldugu birimler. Gecici/anlik seyleri kaydetme. '
      'Ayni anahtari tekrar yazarsan eski deger guncellenir.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'key': {
            'type': 'string',
            'description': 'Kisa etiket (ornek: "isim", "sehir", "meslek").',
          },
          'value': {
            'type': 'string',
            'description': 'Hatirlanacak deger.',
          },
        },
        'required': ['key', 'value'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final key = (args['key'] ?? '').toString().trim();
    final value = (args['value'] ?? '').toString().trim();
    if (key.isEmpty || value.isEmpty) return 'HATA: key ve value gerekli.';
    await memoryStore.remember(key, value);
    return 'Hafizaya yazildi: $key = $value';
  }
}

/// Hafizadaki tum kalici bilgileri okur.
class RecallTool extends Tool {
  @override
  String get name => 'recall';

  @override
  String get description =>
      'Uzun sureli hafizadaki tum kalici bilgileri (kullanici tercihleri, '
      'kisisel notlar) listeler. Kullaniciyla ilgili bir sey hatirlaman '
      'gerektiginde bunu kullan.';

  @override
  Map<String, dynamic> get parameters =>
      {'type': 'object', 'properties': {}};

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final facts = await memoryStore.all();
    if (facts.isEmpty) return 'Hafiza bos.';
    return facts.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }
}

/// Hafizadan bir bilgiyi siler.
class ForgetTool extends Tool {
  @override
  String get name => 'forget';

  @override
  String get description =>
      'Uzun sureli hafizadan bir bilgiyi siler. Kullanici "bunu unut" derse '
      'veya bilgi artik gecerli degilse kullan.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'key': {
            'type': 'string',
            'description': 'Silinecek bilginin anahtari.',
          },
        },
        'required': ['key'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final key = (args['key'] ?? '').toString().trim();
    final ok = await memoryStore.forget(key);
    return ok ? 'Unutuldu: $key' : 'Bulunamadi: $key';
  }
}
