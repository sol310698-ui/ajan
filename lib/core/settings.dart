import 'package:shared_preferences/shared_preferences.dart';

import 'agent/llm_client.dart';

/// Uygulama ayarlari: LLM saglayici secimi + her saglayici icin ayri API
/// anahtari ve model. Saglayici degistiginde anahtarlar kaybolmaz.
class AppSettings {
  static const _kProvider = 'llm_provider';
  static const _kGoogleSearch = 'gemini_google_search';
  static const _legacyGeminiKey = 'gemini_api_key';
  static const _legacyGeminiModel = 'gemini_model';

  static String _keyPref(LlmProvider p) => 'apikey_${p.id}';
  static String _modelPref(LlmProvider p) => 'model_${p.id}';

  LlmProvider provider;
  final Map<LlmProvider, String> apiKeys;
  final Map<LlmProvider, String> models;

  /// Gemini icin: Google'in sunucu tarafi arama (grounding) araci acik mi.
  bool googleSearch;

  AppSettings({
    required this.provider,
    required this.apiKeys,
    required this.models,
    this.googleSearch = false,
  });

  String get apiKey => apiKeys[provider] ?? '';
  String get model =>
      (models[provider]?.isNotEmpty ?? false)
          ? models[provider]!
          : provider.defaultModel;

  bool get hasKey => apiKey.trim().isNotEmpty;

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final keys = <LlmProvider, String>{};
    final models = <LlmProvider, String>{};
    for (final prov in LlmProvider.values) {
      keys[prov] = p.getString(_keyPref(prov)) ?? '';
      models[prov] = p.getString(_modelPref(prov)) ?? '';
    }

    // Eski tek-anahtar surumunden gecis.
    final legacyKey = p.getString(_legacyGeminiKey) ?? '';
    if (legacyKey.isNotEmpty && (keys[LlmProvider.gemini] ?? '').isEmpty) {
      keys[LlmProvider.gemini] = legacyKey;
    }
    final legacyModel = p.getString(_legacyGeminiModel) ?? '';
    if (legacyModel.isNotEmpty && (models[LlmProvider.gemini] ?? '').isEmpty) {
      models[LlmProvider.gemini] = legacyModel;
    }

    return AppSettings(
      provider: LlmProviderX.fromId(p.getString(_kProvider)),
      apiKeys: keys,
      models: models,
      googleSearch: p.getBool(_kGoogleSearch) ?? false,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kProvider, provider.id);
    await p.setBool(_kGoogleSearch, googleSearch);
    for (final prov in LlmProvider.values) {
      await p.setString(_keyPref(prov), apiKeys[prov] ?? '');
      await p.setString(_modelPref(prov), models[prov] ?? '');
    }
    // Geriye donuk uyum icin eski anahtari da guncel tut.
    await p.setString(_legacyGeminiKey, apiKeys[LlmProvider.gemini] ?? '');
  }
}
