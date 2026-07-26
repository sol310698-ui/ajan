import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/routine.dart';
import '../providers/routine_provider.dart';

/// Otonom gorevleri (rutinleri) goruntule / ekle / kaldir.
class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routineProvider);
    final ctrl = ref.read(routineProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11111B),
        title: const Text('Rutinler'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF6C5CE7),
        onPressed: () => _addDialog(context, ctrl),
        child: const Icon(Icons.add),
      ),
      body: routines.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Otonom gorev yok.\nOrnek: "her sabah 8de hava durumunu bildir" '
                  'diye yazarsan ajan buraya bir rutin ekler.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6E6C8A)),
                ),
              ),
            )
          : ListView.builder(
              itemCount: routines.length,
              itemBuilder: (_, i) {
                final r = routines[i];
                return _RoutineTile(r: r, ctrl: ctrl);
              },
            ),
    );
  }

  Future<void> _addDialog(
      BuildContext context, RoutineController ctrl) async {
    final nameCtrl = TextEditingController();
    final promptCtrl = TextEditingController();
    var everyMinutes = 1440; // gunluk varsayilan
    var hour = 8;
    var minute = 0;

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('Yeni rutin',
              style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Ad'),
                ),
                TextField(
                  controller: promptCtrl,
                  style: const TextStyle(color: Colors.white),
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Gorev (ajana verilecek talimat)'),
                ),
                const SizedBox(height: 12),
                const Text('Tekrar', style: TextStyle(color: Color(0xFF9E9CB8))),
                DropdownButton<int>(
                  dropdownColor: const Color(0xFF1E1E2E),
                  value: everyMinutes,
                  isExpanded: true,
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Tek seferlik')),
                    DropdownMenuItem(value: 60, child: Text('Her saat')),
                    DropdownMenuItem(value: 360, child: Text('Her 6 saat')),
                    DropdownMenuItem(value: 1440, child: Text('Her gun')),
                    DropdownMenuItem(value: 10080, child: Text('Her hafta')),
                  ],
                  onChanged: (v) => setD(() => everyMinutes = v ?? 1440),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Ilk saat: ',
                        style: TextStyle(color: Colors.white)),
                    TextButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: c,
                          initialTime: TimeOfDay(hour: hour, minute: minute),
                        );
                        if (t != null) {
                          setD(() {
                            hour = t.hour;
                            minute = t.minute;
                          });
                        }
                      },
                      child: Text(
                        '${hour.toString().padLeft(2, '0')}:'
                        '${minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Color(0xFF6C5CE7)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Vazgec')),
            FilledButton(
              onPressed: () {
                if (promptCtrl.text.trim().isEmpty) return;
                final now = DateTime.now();
                var first =
                    DateTime(now.year, now.month, now.day, hour, minute);
                if (!first.isAfter(now)) {
                  first = first.add(const Duration(days: 1));
                }
                ctrl.add(
                  name: nameCtrl.text.trim().isEmpty
                      ? 'Rutin'
                      : nameCtrl.text.trim(),
                  prompt: promptCtrl.text.trim(),
                  intervalMinutes: everyMinutes,
                  firstRun: first,
                );
                Navigator.pop(c);
              },
              child: const Text('Kur'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineTile extends StatelessWidget {
  final Routine r;
  final RoutineController ctrl;
  const _RoutineTile({required this.r, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final tekrar =
        r.isRecurring ? 'her ${r.intervalMinutes} dk' : 'tek seferlik';
    return Card(
      color: const Color(0xFF1E1E2E),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: ListTile(
        title: Text(r.name,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF9E9CB8))),
            const SizedBox(height: 2),
            Text('$tekrar • sonraki: ${r.nextRun.toString().substring(0, 16)}',
                style:
                    const TextStyle(color: Color(0xFF6E6C8A), fontSize: 12)),
            if (r.lastResult.isNotEmpty)
              Text('Son sonuc: ${r.lastResult}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFF6C5CE7), fontSize: 12)),
          ],
        ),
        isThreeLine: true,
        leading: Switch(
          value: r.enabled,
          activeColor: const Color(0xFF6C5CE7),
          onChanged: (v) => ctrl.toggle(r.id, v),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_arrow, color: Color(0xFF6C5CE7)),
              tooltip: 'Simdi calistir',
              onPressed: () => ctrl.runNow(r.id),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => ctrl.remove(r.id),
            ),
          ],
        ),
      ),
    );
  }
}
