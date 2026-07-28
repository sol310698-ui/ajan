import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_nav.dart';
import 'providers/routine_provider.dart';
import 'ui/chat_screen.dart';
import 'ui/theme.dart';

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
      theme: buildAppTheme(),
      home: const ChatScreen(),
    );
  }
}
