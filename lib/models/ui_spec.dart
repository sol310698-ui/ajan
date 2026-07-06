import 'dart:convert';

/// Ajanin urettigi dinamik ekran tarifi.
/// LLM, create_ui araciyla bu yapiyi doldurur; uygulama canli ekran cizer.
class UiSpec {
  final String title;
  final List<UiComponent> components;

  UiSpec({required this.title, required this.components});

  factory UiSpec.fromMap(Map<String, dynamic> m) {
    final comps = (m['components'] as List? ?? [])
        .whereType<Map>()
        .map((c) => UiComponent.fromMap(Map<String, dynamic>.from(c)))
        .toList();
    return UiSpec(
      title: (m['title'] ?? 'Ekran').toString(),
      components: comps,
    );
  }

  /// LLM bazen tum spec'i tek string (JSON) olarak da gonderebilir.
  static UiSpec? tryParse(dynamic raw) {
    try {
      if (raw is Map) return UiSpec.fromMap(Map<String, dynamic>.from(raw));
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return UiSpec.fromMap(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (_) {}
    return null;
  }
}

/// Ekrandaki tek bir bilesen.
class UiComponent {
  final String type; // text, input, stat, list, button, divider
  final String id;
  final String label;
  final String value;
  final String hint;
  final List<String> items;
  final String action; // button: prompt | submit | close
  final String payload;

  UiComponent({
    required this.type,
    this.id = '',
    this.label = '',
    this.value = '',
    this.hint = '',
    this.items = const [],
    this.action = '',
    this.payload = '',
  });

  factory UiComponent.fromMap(Map<String, dynamic> m) {
    return UiComponent(
      type: (m['type'] ?? 'text').toString(),
      id: (m['id'] ?? '').toString(),
      label: (m['label'] ?? '').toString(),
      value: (m['value'] ?? '').toString(),
      hint: (m['hint'] ?? '').toString(),
      items: (m['items'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      action: (m['action'] ?? '').toString(),
      payload: (m['payload'] ?? '').toString(),
    );
  }
}
