import '../native/native_tools.dart';
import 'tool.dart';

/// Panoyu (clipboard) okur veya yazar.
class ClipboardTool extends Tool {
  @override
  String get name => 'clipboard';
  @override
  String get description =>
      'Cihaz panosunu (clipboard) okur veya yazar. action="get" panodaki '
      'metni dondurur; action="set" ise text degerini panoya kopyalar.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'get veya set.'},
          'text': {'type': 'string', 'description': 'set icin yazilacak metin.'},
        },
        'required': ['action'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) async {
    final action = (args['action'] ?? 'get').toString();
    if (action == 'set') {
      return NativeTools.clipboardSet((args['text'] ?? '').toString());
    }
    final t = await NativeTools.clipboardGet();
    return t.isEmpty ? '(pano bos)' : t;
  }
}

/// Batarya durumu (yuzde + sarj).
class BatteryTool extends Tool {
  @override
  String get name => 'battery_status';
  @override
  String get description =>
      'Cihazin batarya yuzdesini ve sarj durumunu dondurur.';
  @override
  Map<String, dynamic> get parameters =>
      {'type': 'object', 'properties': {}};
  @override
  Future<String> run(Map<String, dynamic> args) => NativeTools.batteryStatus();
}

/// Cihaz bilgisi (model, Android surumu vb.).
class DeviceInfoTool extends Tool {
  @override
  String get name => 'device_info';
  @override
  String get description =>
      'Cihaz modeli, uretici, Android surumu ve ekran gibi temel bilgileri '
      'dondurur.';
  @override
  Map<String, dynamic> get parameters =>
      {'type': 'object', 'properties': {}};
  @override
  Future<String> run(Map<String, dynamic> args) => NativeTools.deviceInfo();
}

/// El fenerini (flash) acar/kapatir.
class TorchTool extends Tool {
  @override
  String get name => 'flashlight';
  @override
  String get description => 'El fenerini (kamera flasi) acar veya kapatir.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'on': {'type': 'boolean', 'description': 'true=ac, false=kapat.'},
        },
        'required': ['on'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) =>
      NativeTools.toggleTorch(args['on'] == true);
}

/// Telefon aramasi baslatir.
class MakeCallTool extends Tool {
  @override
  String get name => 'make_call';
  @override
  String get description =>
      'Verilen numarayi arar. Geri donusu olan onemli bir islem oldugu icin '
      'ONCE confirm ile onay al.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'number': {'type': 'string', 'description': 'Aranacak numara.'},
        },
        'required': ['number'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) =>
      NativeTools.makeCall((args['number'] ?? '').toString());
}

/// Rehberde arama yapar.
class ReadContactsTool extends Tool {
  @override
  String get name => 'read_contacts';
  @override
  String get description =>
      'Rehberde isme gore kisi arar ve numaralariyla dondurur. query bos ise '
      'ilk kisileri listeler. Birine mesaj/arama yapmadan once numarayi buradan '
      'bul.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Aranacak isim (opsiyonel).'},
        },
      };
  @override
  Future<String> run(Map<String, dynamic> args) async {
    final r = await NativeTools.readContacts((args['query'] ?? '').toString());
    return r.isEmpty ? 'Kisi bulunamadi.' : r;
  }
}

/// Son gelen SMS'leri okur.
class ReadSmsTool extends Tool {
  @override
  String get name => 'read_sms';
  @override
  String get description =>
      'Son gelen SMS mesajlarini (gonderen + metin) okur. "son mesajlarim ne", '
      '"gelen kod" gibi isteklerde kullan.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description': 'Kac mesaj okunsun (varsayilan 10).',
          },
        },
      };
  @override
  Future<String> run(Map<String, dynamic> args) async {
    final limit = (args['limit'] is int)
        ? args['limit'] as int
        : int.tryParse('${args['limit']}') ?? 10;
    final r = await NativeTools.readSms(limit);
    return r.isEmpty ? 'SMS bulunamadi.' : r;
  }
}

/// Takvime etkinlik ekler.
class AddCalendarEventTool extends Tool {
  @override
  String get name => 'add_calendar_event';
  @override
  String get description =>
      'Takvime bir etkinlik ekler. start_iso ve end_iso ISO-8601 formatinda '
      'olmali (ornek: 2026-07-27T14:00:00). end verilmezse baslangictan 1 saat '
      'sonrasi alinir.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'Etkinlik basligi.'},
          'description': {'type': 'string', 'description': 'Aciklama (opsiyonel).'},
          'start_iso': {'type': 'string', 'description': 'Baslangic (ISO-8601).'},
          'end_iso': {'type': 'string', 'description': 'Bitis (ISO-8601, opsiyonel).'},
        },
        'required': ['title', 'start_iso'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) async {
    final start = DateTime.tryParse((args['start_iso'] ?? '').toString());
    if (start == null) return 'HATA: gecersiz start_iso.';
    final end = DateTime.tryParse((args['end_iso'] ?? '').toString()) ??
        start.add(const Duration(hours: 1));
    return NativeTools.addCalendarEvent(
      (args['title'] ?? 'Etkinlik').toString(),
      (args['description'] ?? '').toString(),
      start.millisecondsSinceEpoch,
      end.millisecondsSinceEpoch,
    );
  }
}

/// Kurulu uygulamalari listeler.
class ListAppsTool extends Tool {
  @override
  String get name => 'list_apps';
  @override
  String get description =>
      'Cihazda kurulu (baslatilabilir) uygulamalarin adlarini listeler. '
      'open_app icin dogru ismi bulmak istersen kullan.';
  @override
  Map<String, dynamic> get parameters =>
      {'type': 'object', 'properties': {}};
  @override
  Future<String> run(Map<String, dynamic> args) => NativeTools.listApps();
}

/// Medya ses seviyesini ayarlar.
class SetVolumeTool extends Tool {
  @override
  String get name => 'set_volume';
  @override
  String get description => 'Medya ses seviyesini yuzde olarak ayarlar (0-100).';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'percent': {'type': 'integer', 'description': '0-100 arasi.'},
        },
        'required': ['percent'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) {
    final p = (args['percent'] is int)
        ? args['percent'] as int
        : int.tryParse('${args['percent']}') ?? 50;
    return NativeTools.setVolume(p.clamp(0, 100));
  }
}

/// Cihazi titretir.
class VibrateTool extends Tool {
  @override
  String get name => 'vibrate';
  @override
  String get description => 'Cihazi verilen sure (ms) titretir.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'ms': {'type': 'integer', 'description': 'Milisaniye (varsayilan 400).'},
        },
      };
  @override
  Future<String> run(Map<String, dynamic> args) {
    final ms = (args['ms'] is int)
        ? args['ms'] as int
        : int.tryParse('${args['ms']}') ?? 400;
    return NativeTools.vibrate(ms);
  }
}

/// Bir web adresini tarayicida acar.
class OpenUrlTool extends Tool {
  @override
  String get name => 'open_url';
  @override
  String get description =>
      'Bir web adresini (URL) varsayilan tarayicida acar.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': 'Acilacak adres (https://...).'},
        },
        'required': ['url'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) =>
      NativeTools.openUrl((args['url'] ?? '').toString());
}

/// Belirli bir sistem ayar ekranini acar.
class OpenSettingsTool extends Tool {
  @override
  String get name => 'open_settings';
  @override
  String get description =>
      'Bir sistem ayar ekranini acar. panel degerleri: wifi, bluetooth, '
      'location, battery, sound, display, apps, data (mobil veri), nfc, '
      'settings (genel). Wifi/bluetooth gibi seyleri kod ile ac-kapa mumkun '
      'degil; ilgili ayar ekranini acarsin.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'panel': {'type': 'string', 'description': 'Acilacak ayar ekrani.'},
        },
        'required': ['panel'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) =>
      NativeTools.openSettings((args['panel'] ?? 'settings').toString());
}
