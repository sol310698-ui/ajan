import 'package:flutter/material.dart';

import '../../models/ui_spec.dart';
import '../../ui/dynamic_screen.dart';
import '../app_nav.dart';
import 'tool.dart';

/// Ajanin duruma gore dinamik ekran (mini uygulama) uretmesini saglar.
/// LLM ekrani JSON olarak tarif eder; uygulama aninda canli cizer.
class CreateUiTool extends Tool {
  @override
  String get name => 'create_ui';

  @override
  String get description =>
      'Kullaniciya OZEL bir ekran/arayuz olusturur ve aninda acar. '
      'Form, buton panosu, gosterge (dashboard), liste vb. icin kullan. '
      'Bilesenler: text (bilgi), input (veri girisi), stat (etiket+deger), '
      'list (madde listesi), button (aksiyon), divider (ayrac). '
      'Button action turleri: "prompt" (label/payload metnini ajana gonderir), '
      '"submit" (formdaki tum input degerlerini toplayip ajana gonderir), '
      '"close" (ekrani kapatir). Ekrani actiktan sonra kullaniciya kisa bilgi ver.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'Ekran basligi.'},
          'components': {
            'type': 'array',
            'description': 'Ekran bilesenleri (sirayla).',
            'items': {
              'type': 'object',
              'properties': {
                'type': {
                  'type': 'string',
                  'description': 'text | input | stat | list | button | divider',
                },
                'id': {'type': 'string', 'description': 'input icin anahtar.'},
                'label': {'type': 'string'},
                'value': {'type': 'string'},
                'hint': {'type': 'string'},
                'items': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
                'action': {
                  'type': 'string',
                  'description': 'button icin: prompt | submit | close',
                },
                'payload': {
                  'type': 'string',
                  'description': 'button basilinca ajana gidecek metin.',
                },
              },
              'required': ['type'],
            },
          },
        },
        'required': ['title', 'components'],
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final spec = UiSpec.fromMap(args);
    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      return 'HATA: ekran acilamadi (navigator hazir degil).';
    }
    nav.push(MaterialPageRoute(builder: (_) => DynamicScreen(spec: spec)));
    final n = spec.components.length;
    return 'Ekran acildi: "${spec.title}" ($n bilesen).';
  }
}
