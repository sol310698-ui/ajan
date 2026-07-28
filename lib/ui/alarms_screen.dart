import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/alarm.dart';
import '../providers/alarm_provider.dart';
import 'theme.dart';

/// Calendar.DAY_OF_WEEK: 1=Pazar ... 7=Cumartesi. Ekranda Pzt->Paz sirasi.
const _dayOrder = [2, 3, 4, 5, 6, 7, 1];
const _dayLabels = {
  2: 'Pzt',
  3: 'Sal',
  4: 'Car',
  5: 'Per',
  6: 'Cum',
  7: 'Cmt',
  1: 'Paz',
};

class AlarmsScreen extends ConsumerWidget {
  const AlarmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarms = ref.watch(alarmProvider);
    final ctrl = ref.read(alarmProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Alarmlar'),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.brand),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () => _edit(context, ctrl, null),
        child: const Icon(Icons.add),
      ),
      body: alarms.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Alarm yok.\nSag alttaki + ile yeni alarm kur.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textFaint),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: alarms.length,
              itemBuilder: (_, i) {
                final a = alarms[i];
                return _AlarmTile(alarm: a, ctrl: ctrl,
                    onTap: () => _edit(context, ctrl, a));
              },
            ),
    );
  }

  Future<void> _edit(
      BuildContext context, AlarmController ctrl, Alarm? existing) async {
    var hour = existing?.hour ?? 8;
    var minute = existing?.minute ?? 0;
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final days = <int>{...(existing?.days ?? const [])};
    var vibrate = existing?.vibrate ?? true;
    var sound = existing?.sound ?? true;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(c).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(existing == null ? 'Yeni alarm' : 'Alarmi duzenle',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 16),
              // Buyuk saat gostergesi + degistir
              Center(
                child: InkWell(
                  onTap: () async {
                    final t = await showTimePicker(
                      context: c,
                      initialTime: TimeOfDay(hour: hour, minute: minute),
                    );
                    if (t != null) {
                      setS(() {
                        hour = t.hour;
                        minute = t.minute;
                      });
                    }
                  },
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:'
                    '${minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 56,
                        fontWeight: FontWeight.w300),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Tekrar',
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: _dayOrder.map((d) {
                  final on = days.contains(d);
                  return ChoiceChip(
                    label: Text(_dayLabels[d]!),
                    selected: on,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                        color: on ? Colors.white : AppColors.textSecondary),
                    backgroundColor: AppColors.surface,
                    selectedColor: AppColors.primary,
                    onSelected: (_) => setS(() {
                      if (on) {
                        days.remove(d);
                      } else {
                        days.add(d);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: labelCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(labelText: 'Etiket (opsiyonel)'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ses',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                value: sound,
                activeColor: AppColors.primary,
                onChanged: (v) => setS(() => sound = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Titresim',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                value: vibrate,
                activeColor: AppColors.primary,
                onChanged: (v) => setS(() => vibrate = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (existing != null)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent),
                      label: const Text('Sil',
                          style: TextStyle(color: Colors.redAccent)),
                      onPressed: () {
                        ctrl.remove(existing.id);
                        Navigator.pop(c);
                      },
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      final list = days.toList()..sort();
                      if (existing == null) {
                        ctrl.add(
                          hour: hour,
                          minute: minute,
                          label: labelCtrl.text.trim(),
                          days: list,
                          vibrate: vibrate,
                          sound: sound,
                        );
                      } else {
                        existing.hour = hour;
                        existing.minute = minute;
                        existing.label = labelCtrl.text.trim();
                        existing.days = list;
                        existing.vibrate = vibrate;
                        existing.sound = sound;
                        ctrl.update(existing);
                      }
                      Navigator.pop(c);
                    },
                    child: const Text('Kaydet'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlarmTile extends StatelessWidget {
  final Alarm alarm;
  final AlarmController ctrl;
  final VoidCallback onTap;
  const _AlarmTile(
      {required this.alarm, required this.ctrl, required this.onTap});

  String _daysText() {
    if (alarm.days.isEmpty) return 'Tek sefer';
    if (alarm.days.length == 7) return 'Her gun';
    final ordered = _dayOrder.where((d) => alarm.days.contains(d));
    return ordered.map((d) => _dayLabels[d]).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final dim = !alarm.enabled;
    return Card(
      color: AppColors.card,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: onTap,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(alarm.timeText,
                style: TextStyle(
                    color: dim ? AppColors.textFaint : Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w300)),
            const SizedBox(width: 10),
            if (alarm.label.isNotEmpty)
              Expanded(
                child: Text(alarm.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
          ],
        ),
        subtitle: Text(_daysText(),
            style: const TextStyle(color: AppColors.textFaint, fontSize: 12)),
        trailing: Switch(
          value: alarm.enabled,
          activeColor: AppColors.primary,
          onChanged: (v) => ctrl.setEnabled(alarm.id, v),
        ),
      ),
    );
  }
}
