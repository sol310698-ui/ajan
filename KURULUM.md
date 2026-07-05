# Ajan — Dusunebilen Telefon Ajani

Gemini function calling + ajan dongusu + Termux komut kopruso + native Android
araclari. Chat arayuzunden soru sor veya is ver; ajan gerektikce telefonda
islem yapar.

## Mimari

```
lib/
  main.dart                       -> uygulama girisi
  models/chat_message.dart        -> mesaj + tool call/result modelleri
  core/
    agent/
      llm_client.dart             -> Gemini API (function calling)
      agent_loop.dart             -> dusun-cagir-degerlendir dongusu
      tool_registry.dart          -> araclarin kaydi (yeni yetenek = 1 satir)
    tools/
      tool.dart                   -> arac temel sinifi
      shell_tool.dart             -> run_shell (Termux)
      device_tools.dart           -> open_app, send_sms, get_location, notify
    termux/termux_bridge.dart     -> Termux kopruso (native channel)
    native/native_tools.dart      -> native islemler kopruso
  providers/agent_provider.dart   -> Riverpod state + system prompt
  ui/                             -> chat ekrani + widget'lar
android/app/src/main/
  kotlin/.../MainActivity.kt      -> platform channel + Termux RUN_COMMAND
  AndroidManifest.xml             -> izinler
```

## Kurulum (Termux)

Bu bir iskelet; once flutter projesi olarak canlandirilmali.

```bash
# 1) Bos flutter projesi olustur (gradle vs. dosyalari icin)
cd ~
flutter create --org com.sametdemiral --project-name ajan ajan_base

# 2) Bu zip'in icerigini uzerine kopyala
cd /sdcard/Download/v2      # zip'i buraya actin
cp -rf lib pubspec.yaml KURULUM.md ~/ajan_base/
cp -f android/app/src/main/AndroidManifest.xml ~/ajan_base/android/app/src/main/
mkdir -p ~/ajan_base/android/app/src/main/kotlin/com/sametdemiral/ajan
cp -f android/app/src/main/kotlin/com/sametdemiral/ajan/MainActivity.kt \
  ~/ajan_base/android/app/src/main/kotlin/com/sametdemiral/ajan/

cd ~/ajan_base
flutter pub get
```

### Kotlin coroutines bagimliligi

`android/app/build.gradle` icindeki `dependencies { }` blokuna ekle:

```gradle
implementation "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3"
```

### applicationId

`android/app/build.gradle` icinde `applicationId` degeri
`com.sametdemiral.ajan` olmali (paket adiyla eslesmeli).

## Termux tarafi (bir kez)

```bash
# allow-external-apps aktif et
mkdir -p ~/.termux
echo "allow-external-apps=true" >> ~/.termux/termux.properties
termux-reload-settings
```

Not: Ajan app'i ile Termux **ayni imza** ile imzalanmali ya da Termux
ayarindan izin verilmeli. En kolayi ikisini de kendi keystore'unla imzala.

## Calistir

```bash
flutter build apk --release
# veya CI/CD ile arm64:
# flutter build apk --release --target-platform android-arm64
```

Ilk acilista sag ustteki dislicarktan **Gemini API anahtarini** gir.
Model varsayilani `gemini-2.0-flash`.

## Ilk test

Chat'e yaz:
- "pil durumunu ogren" -> ajan `run_shell` ile `termux-battery-status` calistirir
- "indirilenler klasorunde kac dosya var" -> `ls ~/storage/downloads | wc -l`
- "bana bildirim gonder: test" -> `notify` araci

## Yeni yetenek ekleme

1. `core/tools/` altinda `Tool`'u genisleten yeni sinif yaz.
2. `tool_registry.dart` icinde `_register([...])` listesine ekle.
3. Bitti — model otomatik gorur ve kullanir.
```
