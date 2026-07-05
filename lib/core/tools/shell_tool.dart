import '../termux/termux_bridge.dart';
import 'tool.dart';

/// Telefonda (Termux uzerinden) shell komutu calistirir.
/// Ajanin en guclu araci: python, curl, git, dosya islemleri vs.
class ShellTool extends Tool {
  @override
  String get name => 'run_shell';

  @override
  String get description =>
      'Telefonda Termux uzerinden bir Linux shell komutu calistirir. '
      'Dosya islemleri, python, curl, git, sistem bilgisi vb. icin kullan. '
      'Cikti (stdout+stderr) geri dondurulur. Tehlikeli/geri donusu olmayan '
      'komutlarda dikkatli ol.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'Calistirilacak tam shell komutu.',
          },
        },
        'required': ['command'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final cmd = (args['command'] ?? '').toString().trim();
    if (cmd.isEmpty) return 'HATA: bos komut.';
    return TermuxBridge.run(cmd);
  }
}
