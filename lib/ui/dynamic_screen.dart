import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ui_spec.dart';
import '../providers/agent_provider.dart';

/// Ajanin urettigi UiSpec'i canli bir ekran olarak cizer.
/// Butonlar tekrar ajana mesaj gonderebilir (prompt/submit) veya ekrani kapatir.
class DynamicScreen extends ConsumerStatefulWidget {
  final UiSpec spec;
  const DynamicScreen({super.key, required this.spec});

  @override
  ConsumerState<DynamicScreen> createState() => _DynamicScreenState();
}

class _DynamicScreenState extends ConsumerState<DynamicScreen> {
  final Map<String, TextEditingController> _inputs = {};

  @override
  void dispose() {
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String id) =>
      _inputs.putIfAbsent(id, () => TextEditingController());

  void _handleAction(UiComponent b) {
    switch (b.action) {
      case 'close':
        Navigator.of(context).maybePop();
        break;
      case 'submit':
        final data = _inputs.entries
            .map((e) => '${e.key}=${e.value.text}')
            .join(', ');
        final msg = b.payload.isNotEmpty
            ? '${b.payload} [$data]'
            : 'Form gonderildi: [$data]';
        Navigator.of(context).maybePop();
        ref.read(agentProvider.notifier).sendUserMessage(msg);
        break;
      case 'prompt':
      default:
        final msg = b.payload.isNotEmpty ? b.payload : b.label;
        Navigator.of(context).maybePop();
        ref.read(agentProvider.notifier).sendUserMessage(msg);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11111B),
        title: Text(widget.spec.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: widget.spec.components.map(_build).toList(),
      ),
    );
  }

  Widget _build(UiComponent c) {
    switch (c.type) {
      case 'text':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(c.value.isNotEmpty ? c.value : c.label,
              style: const TextStyle(color: Colors.white, fontSize: 15)),
        );
      case 'input':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextField(
            controller: _ctrl(c.id.isNotEmpty ? c.id : c.label),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: c.label,
              hintText: c.hint,
              filled: true,
              fillColor: const Color(0xFF1E1E2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        );
      case 'stat':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(c.label,
                  style: const TextStyle(color: Color(0xFF9E9CB8), fontSize: 14)),
              Text(c.value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        );
      case 'list':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: c.items
              .map((it) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      const Text('•  ',
                          style: TextStyle(color: Color(0xFF6C5CE7))),
                      Expanded(
                          child: Text(it,
                              style: const TextStyle(color: Colors.white))),
                    ]),
                  ))
              .toList(),
        );
      case 'button':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => _handleAction(c),
              child: Text(c.label),
            ),
          ),
        );
      case 'divider':
        return const Divider(color: Color(0xFF2A2A3A), height: 24);
      default:
        return const SizedBox.shrink();
    }
  }
}
