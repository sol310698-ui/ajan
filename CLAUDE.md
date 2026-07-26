# CLAUDE.md

Bu dosya, bu depoda çalışan Claude Code (ve diğer geliştiriciler) için projenin
**mantığını ve mimarisini** özetler. Amaç: koda dalmadan önce "bu proje nasıl
düşünür, nasıl çalışır" sorusunu tek dosyada cevaplamak.

> Kurulum/derleme adımları için ayrıca `KURULUM.md`'ye bak.

---

## 1. Proje nedir?

**Ajan**, Android telefonda çalışan, **düşünebilen kişisel bir yapay zeka
ajanıdır**. Sıradan bir sohbet botu değil: kullanıcının işini sadece anlatmaz,
elindeki araçlarla telefonda **gerçekten yapar**.

- Yazılım: **Flutter / Dart** (UI + ajan mantığı), **Kotlin** (native Android).
- Beyin: **Google Gemini** (varsayılan `gemini-2.5-flash`) — *function calling*
  ile araç çağırır.
- Kaslar: Termux üzerinden shell, native cihaz araçları, ekran otomasyonu
  (erişilebilirlik), dinamik UI üretimi ve sesli konuşma.

Temel felsefe: **LLM karar verir, araçlar iş yapar.** Yeni bir yetenek eklemek =
yeni bir `Tool` sınıfı + register'a bir satır. Model onu otomatik görür ve kullanır.

---

## 2. Ana döngü (agent loop) — projenin kalbi

Tüm mantık `lib/core/agent/agent_loop.dart` içindeki **düşün → çağır → değerlendir**
döngüsüdür:

```
1. Kullanıcı mesajı geçmişe eklenir.
2. LLM çağrılır (system prompt + geçmiş + araç tanımları).
3. LLM araç çağırdıysa  -> araçlar çalıştırılır, sonuçlar geçmişe eklenir -> 2'ye dön.
4. LLM düz metin döndürdüyse -> nihai cevap, döngü biter.
```

- Her adımda `onEvent` ile UI canlı güncellenir (mesajlar akar).
- `maxSteps` (provider'da 15) sonsuz döngüye karşı güvenlik sınırıdır.
- Araç çağrısı `_execute` içinde try/catch ile izole edilir; bir araç patlarsa
  hata modele `ToolResult(ok:false)` olarak geri beslenir, döngü ölmez.

Bu döngü sayesinde ajan karmaşık görevleri kendi kendine küçük adımlara bölüp
zincirler (örn: ekranı oku → butona dokun → sonucu oku → yaz → onay al → gönder).

---

## 3. Mimari harita

```
lib/
  main.dart                       -> uygulama girişi (dark tema, global navigator)
  models/
    chat_message.dart             -> Role (user/assistant/tool/system), ToolCall, ToolResult, ChatMessage
    ui_spec.dart                  -> create_ui'nin ürettiği dinamik ekran tarifi
  core/
    app_nav.dart                  -> global navigatorKey (araçların UI/dialog açabilmesi için)
    agent/
      agent_loop.dart             -> düşün-çağır-değerlendir döngüsü (§2)
      llm_client.dart             -> Gemini API (function calling + retry/backoff)
      tool_registry.dart          -> tüm araçların kaydı (yeni yetenek = 1 satır)
    tools/
      tool.dart                   -> Tool soyut temel sınıfı
      shell_tool.dart             -> run_shell (Termux)
      device_tools.dart           -> open_app, send_sms, get_location, notify
      schedule_tools.dart         -> schedule_notification (zamanlı hatırlatma)
      screen_tool.dart            -> screen_control (erişilebilirlik otomasyonu)
      ui_tool.dart                -> create_ui (dinamik ekran üretimi)
      confirm_tool.dart           -> confirm (kullanıcıdan onay isteme)
    termux/termux_bridge.dart     -> Termux köprüsü (RUN_COMMAND intent)
    native/
      native_tools.dart           -> cihaz işlemleri + wake lock köprüsü
      automation.dart             -> ekran okuma/dokunma/yazma + overlay köprüsü
    voice/voice_service.dart      -> STT (sesli giriş) + TTS (seslendirme)
  providers/agent_provider.dart   -> Riverpod state + SYSTEM PROMPT
  ui/                             -> chat_screen, dynamic_screen, widget'lar

android/app/src/main/kotlin/.../   
  MainActivity.kt                 -> platform channel (ajan/native) + Termux RUN_COMMAND
  AgentService.kt                 -> kalıcı ön plan servisi (arka planda ölmesin)
  AjanAccessibilityService.kt     -> ekran okuma/otomasyon
  ReminderReceiver.kt             -> zamanlı bildirim alıcısı
  OverlayService.kt               -> yüzen buton
```

---

## 4. Katmanlar ve sorumlulukları

### LLM istemcisi — `llm_client.dart`
- Gemini `generateContent` endpoint'ini çağırır (`systemInstruction` + `contents`
  + `tools.functionDeclarations`).
- `ChatMessage` geçmişini Gemini formatına çevirir: `user` → user, `assistant` →
  model (metin + `functionCall`), `tool` → user içinde `functionResponse`.
- **Dayanıklılık:** telefon uykuya girer / ağ anlık koparsa istek düşebilir.
  5xx / 429 / SocketException durumlarında **exponential backoff** (0.8s → 6s,
  `maxRetries=3`) ile otomatik tekrar dener; kullanıcıya hata yansımaz.

### Araç sistemi — `tools/` + `tool_registry.dart`
- Her araç `Tool` sınıfını genişletir: `name`, `description`, `parameters`
  (JSON Schema) ve `run(args)`.
- `toDeclaration()` Gemini function-declaration formatına çevirir.
- `run`'ın döndürdüğü metin **modele geri beslenir** — bu yüzden özetleyici,
  net ve ham çıktıya boğmayan olmalı.
- `ToolRegistry` yapılandırıcısında araçlar tek listede register edilir.

Kayıtlı araçlar:
| Araç | İş |
|------|----|
| `run_shell` | Termux'ta Linux komutu (python, curl, git, dosya, paket) |
| `open_app` | Uygulama açar |
| `send_sms` | SMS gönderir |
| `get_location` | Konum döndürür |
| `notify` | Bildirim gösterir |
| `schedule_notification` | Gecikmeli/zamanlı hatırlatma (sleep KULLANMAZ) |
| `create_ui` | Kullanıcıya özel dinamik ekran/mini uygulama üretir |
| `screen_control` | Ekranda gezinip otomasyon yapar (erişilebilirlik) |
| `confirm` | Riskli işlemden önce kullanıcı onayı ister (döngüyü bloklar) |

### Native köprü — `native_tools.dart` / `automation.dart` / `termux_bridge.dart`
- Hepsi tek bir `MethodChannel('ajan/native')` üzerinden Kotlin
  `MainActivity`'ye gider.
- `startAgentTask` / `stopAgentTask` → görev süresince **wake lock** alır/bırakır
  (batarya dostu; sadece iş varken uyanık).
- Termux köprüsü `com.termux.RUN_COMMAND` intent'i ile komut gönderir, çıktı
  dosyaya yazılır ve geri okunur.

### Ses — `voice_service.dart`
- STT: mikrofonu dinler (`tr_TR`), tanınan metni geri döndürür.
- TTS: cevapları seslendirir (`tr-TR`, ayarlanabilir hız). Kuyruk modu
  (`QUEUE_ADD`) ile ara adımlar birbirini kesmeden sırayla okunur.
- Ayarlar (hız, otomatik seslendirme) `SharedPreferences`'ta saklanır.

### State — `agent_provider.dart` (Riverpod)
- `AgentNotifier` sohbet geçmişini, `busy` ve `hasKey` durumunu tutar.
- API anahtarı ve model `SharedPreferences`'ta saklanır (ilk açılışta girilir).
- `sendUserMessage`: geçmişe ekler → wake lock al → `AgentLoop.run` → bitince
  wake lock bırak.
- **`kSystemPrompt` burada tanımlıdır** — ajanın davranış kurallarının kaynağı.

---

## 5. Ajanın davranış kuralları (system prompt özeti)

`agent_provider.dart` içindeki `kSystemPrompt` ajanın kişiliğini belirler:

- Türkçe, kısa ve net konuş.
- Bir işi araçla yapabiliyorsan **tahmin etme, aracı çağır**.
- Karmaşık görevi küçük adımlara böl, adımları kendin zincirle, tamamlamadan durma.
- Güvenli/geri alınabilir işlemler için tekrar tekrar onay isteme; yap ve özetle.
- **Geri dönüşü olmayan/tehlikeli işlemlerden önce `confirm` ile onay al**
  (SMS/mesaj gönderme, arama, silme, satın alma, otomasyonla gönderme).
  `"reddedildi"` dönerse işlemi YAPMA.
- Zamanlı hatırlatma → `schedule_notification` (asla `run_shell + sleep` değil).
- Ekranda otomasyon yaparken (`screen_control`) her adımdan önce ne yapacağını
  tek cümleyle söyle → kullanıcı canlı takip etsin.
- Uzun komutları arka plana al (`komut > log.txt 2>&1 &`) ve sonra kontrol et.

---

## 6. Yeni yetenek nasıl eklenir?

1. `lib/core/tools/` altında `Tool`'u genişleten yeni bir sınıf yaz
   (`name`, `description`, `parameters`, `run`).
2. `lib/core/agent/tool_registry.dart` içindeki `_register([...])` listesine ekle.
3. Native bir işlem gerekiyorsa `MainActivity.kt`'de yeni bir method channel
   case'i ekle ve `native_tools.dart`/`automation.dart`'a köprü metodu yaz.
4. Bitti — model `description` sayesinde aracı otomatik görür ve kullanır.

> İyi bir `description` = modelin aracı doğru zamanda çağırmasının anahtarıdır.
> Ne işe yaradığını ve **ne zaman kullanılacağını** açıkça yaz.

---

## 7. Native / Android tarafı

- Tek platform channel: **`ajan/native`** (tüm Dart↔Kotlin trafiği buradan).
- Servisler: `AgentService` (kalıcı ön plan, arka planda ölmeme),
  `AjanAccessibilityService` (ekran okuma/otomasyon), `ReminderReceiver`
  (exact alarm ile zamanlı bildirim), `OverlayService` (yüzen buton).
- Önemli izinler (`AndroidManifest.xml`): `INTERNET`, `RECORD_AUDIO`, `SEND_SMS`,
  `POST_NOTIFICATIONS`, konum, `FOREGROUND_SERVICE(_DATA_SYNC)`, `WAKE_LOCK`,
  `SCHEDULE/USE_EXACT_ALARM`, `com.termux.permission.RUN_COMMAND`,
  `SYSTEM_ALERT_WINDOW`.
- Termux ile aynı imza gerekir veya Termux ayarından `allow-external-apps=true`.

---

## 8. Konvansiyonlar (kod yazarken uy)

- **Dil:** kod içi yorumlar, string'ler ve dokümanlar **Türkçe** (çoğunlukla
  ASCII, şapkasız — mevcut stille uyumlu kal).
- Araç isimleri `snake_case` (model bu isimle çağırır).
- `run` çıktısı modele gider → kısa ve özet tut.
- State yönetimi **Riverpod** `StateNotifier` ile; UI'da `ConsumerWidget`.
- Native çağrılar her zaman `ajan/native` channel'ından, hata yutan try/catch ile.
- Yeni bir tehlikeli işlem eklerken system prompt kuralına uygun olarak
  `confirm` akışını dahil et.
