import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/log/app_log.dart';
import 'theme.dart';

/// Uygulama kayitlari (log). Cokme/hata teshisi icin; son satir genelde
/// nerede coktugunu gosterir.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});
  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  List<String> _lines = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => setState(() => _lines = AppLog.lines());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Kayitlar (log)'),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.brand),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Kopyala',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _lines.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Kayitlar kopyalandi.')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Temizle',
            onPressed: () async {
              await AppLog.clear();
              _refresh();
            },
          ),
        ],
      ),
      body: _lines.isEmpty
          ? const Center(
              child: Text('Kayit yok.',
                  style: TextStyle(color: AppColors.textFaint)))
          : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: _lines.length,
              itemBuilder: (_, i) {
                final line = _lines[i];
                final isErr = line.contains('[E]');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: SelectableText(
                    line,
                    style: TextStyle(
                      color: isErr
                          ? const Color(0xFFFFB4A9)
                          : AppColors.textSecondary,
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
