import '../native/automation.dart';
import 'tool.dart';

/// Ekranda gezinme + otomasyon: ekrani okur, dokunur, yazar, kaydirir,
/// geri/ana ekran gibi genel islemleri yapar. (Erisilebilirlik gerekir.)
class ScreenControlTool extends Tool {
  @override
  String get name => 'screen_control';

  @override
  String get description =>
      'Telefon ekraninda senin yerine islem yapar (erisilebilirlik). '
      'action degerleri: '
      '"read" (ekrandaki metinleri oku - once bunu kullanip ekrani gor), '
      '"screenshot" (ekranin GORSELINI al ve gor - metin okuma yanlis/eksikse, '
      'ikonlari, resimdeki yaziyi veya butonlarin gercekte ne oldugunu anlamak '
      'icin bunu kullan; goruntuyu dogrudan gorursun), '
      '"tap" (text ile eslesen ogeye dokun), '
      '"type" (yazilabilir alana text yaz), '
      '"scroll" (direction: up/down), '
      '"back"/"home"/"recents"/"notifications" (genel islemler). '
      'Bir uygulamada is yaparken once "read" ile ekrani gor; etiketler yanlis '
      'veya yetersizse "screenshot" ile gorsele bak, sonra "tap"/"type" ile ilerle.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'description': 'read | tap | type | scroll | back | home | recents | notifications',
          },
          'text': {
            'type': 'string',
            'description': 'tap icin dokunulacak metin; type icin yazilacak metin.',
          },
          'direction': {
            'type': 'string',
            'description': 'scroll icin: up veya down.',
          },
        },
        'required': ['action'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final action = (args['action'] ?? '').toString();
    final text = (args['text'] ?? '').toString();
    final dir = (args['direction'] ?? 'down').toString();

    if (!await Automation.isAccessibilityOn()) {
      await Automation.openAccessibilitySettings();
      return 'Erisilebilirlik kapali. Acilan ayar ekranindan "Ajan"i etkinlestir, '
          'sonra tekrar dene.';
    }

    switch (action) {
      case 'read':
        return 'EKRAN:\n${await Automation.readScreen()}';
      case 'screenshot':
        final b64 = await Automation.screenshot();
        if (b64.isEmpty) {
          return 'Ekran goruntusu alinamadi (Android 11+ gerekir ve '
              'erisilebilirlik acik olmali).';
        }
        // AgentLoop bu isareti gorunce goruntuyu modele gorsel olarak iletir.
        return 'IMG::$b64';
      case 'tap':
        return await Automation.tap(text);
      case 'type':
        return await Automation.type(text);
      case 'scroll':
        return await Automation.scroll(dir);
      case 'back':
      case 'home':
      case 'recents':
      case 'notifications':
        return await Automation.global(action);
      default:
        return 'Bilinmeyen islem: $action';
    }
  }
}
