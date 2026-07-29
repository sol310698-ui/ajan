import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_nav.dart';
import 'core/log/app_log.dart';
import 'providers/agent_provider.dart';
import 'providers/routine_provider.dart';
import 'ui/chat_screen.dart';
import 'ui/theme.dart';

/// Uygulama ve yuzen baloncuk AYNI motoru/durumu paylassin diye global kap.
final ProviderContainer appContainer = ProviderContainer();

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppLog.init();

    // Dart tarafi hatalari log'a dussun.
    FlutterError.onError = (details) {
      AppLog.e('FlutterError: ${details.exceptionAsString()}');
      FlutterError.presentError(details);
    };
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      AppLog.e('PlatformError: $error');
      return true;
    };

    _setupOverlayChannel();
    runApp(UncontrolledProviderScope(
      container: appContainer,
      child: const AjanApp(),
    ));
  }, (error, stack) {
    AppLog.e('Uncaught: $error\n$stack');
  });
}

/// Yuzen baloncuktan (native OverlayService) gelen mesajlari ANA ajana iletir.
/// Boylece kullanici uygulamaya donmeden, ayni sohbette gorevi yonlendirebilir.
void _setupOverlayChannel() {
  const ch = MethodChannel('ajan/overlay_in');
  ch.setMethodCallHandler((call) async {
    if (call.method == 'ask') {
      final prompt = (call.arguments as String?)?.trim() ?? '';
      if (prompt.isEmpty) return '';
      try {
        return await appContainer
            .read(agentProvider.notifier)
            .askFromOverlay(prompt);
      } catch (e) {
        return 'Hata: $e';
      }
    }
    return null;
  });
}

class AjanApp extends ConsumerWidget {
  const AjanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rutin zamanlayicisini uygulama acilir acilmaz baslat.
    ref.watch(routineProvider);

    return MaterialApp(
      title: 'Ajan',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: buildAppTheme(),
      home: const ChatScreen(),
    );
  }
}
