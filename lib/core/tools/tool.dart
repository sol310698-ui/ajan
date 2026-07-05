/// Ajanin kullanabilecegi tek bir yetenek (arac).
///
/// Yeni bir yetenek eklemek icin bu sinifi genislet ve ToolRegistry'e ekle.
abstract class Tool {
  /// LLM'in cagirirken kullanacagi benzersiz isim (snake_case).
  String get name;

  /// Modelin ne zaman kullanacagini anlamasi icin net aciklama.
  String get description;

  /// Parametre semasi (JSON Schema - Gemini "parameters" formati).
  Map<String, dynamic> get parameters;

  /// Araci calistirir. args model tarafindan uretilen parametrelerdir.
  /// Donen metin modele geri beslenir, o yuzden ozetleyici ve net olmali.
  Future<String> run(Map<String, dynamic> args);

  /// Gemini functionDeclarations formatina cevirir.
  Map<String, dynamic> toDeclaration() => {
        'name': name,
        'description': description,
        'parameters': parameters,
      };
}
