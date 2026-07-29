import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/agent/headless_agent.dart';
import 'core/app_nav.dart';
import 'providers/routine_provider.dart';
import 'ui/chat_screen.dart';
import 'ui/theme.dart';

void main() {
  runApp(const ProviderScope(child: AjanApp()));
}

/// Yuzen baloncuk (overlay) icin ayri, basssiz giris noktasi. Native
/// OverlayService bu motoru calistirir ve 'ajan/overlay' kanalindan
/// 'ask' cagirir; biz sohbet-odakli ajani calistirip metni geri veririz.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('ajan/overlay');
  ch.setMethodCallHandler((call) async {
    if (call.method == 'ask') {
      final prompt = (call.arguments as String?)?.trim() ?? '';
      if (prompt.isEmpty) return '';
      try {
        return await runAgentOnce(prompt, maxSteps: 10, chatOnly: true);
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
    // Rutin zamanlayicisini uygulama acilir acilmaz baslat (vadesi gelen
    // otonom gorevler arka planda calissin).
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
