import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_nav.dart';
import 'providers/routine_provider.dart';
import 'ui/chat_screen.dart';

void main() {
  runApp(const ProviderScope(child: AjanApp()));
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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
      ),
      home: const ChatScreen(),
    );
  }
}
