import '../native/native_tools.dart';
import 'tool.dart';

class OpenAppTool extends Tool {
  @override
  String get name => 'open_app';
  @override
  String get description =>
      'Bir uygulamayi acar. Uygulama adi (ornek: "WhatsApp", "Ayarlar") '
      'veya paket adi verilebilir.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Uygulama adi veya paket adi.',
          },
        },
        'required': ['query'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) =>
      NativeTools.openApp((args['query'] ?? '').toString());
}

class SendSmsTool extends Tool {
  @override
  String get name => 'send_sms';
  @override
  String get description => 'Verilen numaraya SMS gonderir.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'number': {'type': 'string', 'description': 'Telefon numarasi.'},
          'message': {'type': 'string', 'description': 'Mesaj metni.'},
        },
        'required': ['number', 'message'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) => NativeTools.sendSms(
        (args['number'] ?? '').toString(),
        (args['message'] ?? '').toString(),
      );
}

class LocationTool extends Tool {
  @override
  String get name => 'get_location';
  @override
  String get description => 'Cihazin anlik konumunu (enlem,boylam) dondurur.';
  @override
  Map<String, dynamic> get parameters =>
      {'type': 'object', 'properties': {}};
  @override
  Future<String> run(Map<String, dynamic> args) => NativeTools.getLocation();
}

class NotifyTool extends Tool {
  @override
  String get name => 'notify';
  @override
  String get description => 'Cihazda bir bildirim gosterir.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'Bildirim basligi.'},
          'body': {'type': 'string', 'description': 'Bildirim metni.'},
        },
        'required': ['title', 'body'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) => NativeTools.notify(
        (args['title'] ?? '').toString(),
        (args['body'] ?? '').toString(),
      );
}
