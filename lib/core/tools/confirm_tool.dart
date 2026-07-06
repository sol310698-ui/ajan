import 'package:flutter/material.dart';

import '../app_nav.dart';
import 'tool.dart';

/// Onemli/geri donusu olmayan islemlerden ONCE kullanicidan onay ister.
/// Ajan donguyu bloklar ve kullanici karar verene kadar bekler.
class ConfirmTool extends Tool {
  @override
  String get name => 'confirm';

  @override
  String get description =>
      'Onemli veya geri donusu olmayan bir islemden ONCE kullanicidan onay al. '
      'Mesaj/SMS gonderme, arama yapma, silme, satin alma, otomasyonla (screen_control) '
      'bir sey gonderme/onaylama gibi adimlardan once MUTLAKA cagir. '
      'Kullanici onaylarsa "onaylandi" doner (islemi yap), '
      'reddederse "reddedildi" doner (islemi YAPMA, iptal et).';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'question': {
            'type': 'string',
            'description': 'Kullaniciya sorulacak net onay sorusu. '
                'Ornek: "Ahmet\'e \'geliyorum\' mesajini gondereyim mi?"',
          },
        },
        'required': ['question'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final question = (args['question'] ?? 'Bu islemi yapayim mi?').toString();
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return 'reddedildi (arayuz hazir degil, guvenlik icin iptal)';

    final ok = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Onay', style: TextStyle(color: Colors.white)),
        content: Text(question,
            style: const TextStyle(color: Color(0xFFD5D3E8), fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgec', style: TextStyle(color: Colors.redAccent)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    return ok == true
        ? 'onaylandi (devam et)'
        : 'reddedildi (islemi yapma, iptal et)';
  }
}
