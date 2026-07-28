import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/routine.dart';
import '../providers/routine_provider.dart';
import 'theme.dart';

/// Bir rutinin detayini ve SON CALISMA SONUCUNU tam olarak gosterir.
class RoutineDetailScreen extends ConsumerWidget {
  final String routineId;
  const RoutineDetailScreen({super.key, required this.routineId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routineProvider);
    final ctrl = ref.read(routineProvider.notifier);
    Routine? r;
    for (final e in routines) {
      if (e.id == routineId) r = e;
    }

    if (r == null) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Text('Rutin silinmis.',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    final routine = r;
    final tekrar = routine.isRecurring
        ? 'Her ${routine.intervalMinutes} dakikada bir'
        : 'Tek seferlik';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(routine.name),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.brand),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Simdi calistir',
            onPressed: () {
              ctrl.runNow(routine.id);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Rutin calistiriliyor... sonuc birazdan burada.'),
              ));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card([
            _row('Durum', routine.enabled ? 'Aktif' : 'Kapali'),
            _row('Tekrar', tekrar),
            _row('Sonraki calisma',
                routine.nextRun.toString().substring(0, 16)),
            if (routine.lastRun != null)
              _row('Son calisma',
                  routine.lastRun!.toString().substring(0, 16)),
          ]),
          const SizedBox(height: 16),
          const Text('GOREV',
              style: TextStyle(
                  color: AppColors.primaryLight,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _card([
            SelectableText(routine.prompt,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14, height: 1.4)),
          ]),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('SON SONUC',
                  style: TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 12,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700)),
              if (routine.lastResult.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Kopyala'),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: routine.lastResult));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Kopyalandi.')),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          _card([
            routine.lastResult.isEmpty
                ? const Text('Henuz calismadi. Sag ustteki oynat tusuyla '
                    'hemen deneyebilirsin.',
                    style: TextStyle(color: AppColors.textFaint))
                : SelectableText(routine.lastResult,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        height: 1.45)),
          ]),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(k,
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );

  Widget _card(List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}
