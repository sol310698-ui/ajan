import 'package:flutter/material.dart';

import '../core/store/memory_store.dart';

/// Ajanin uzun sureli hafizasini goruntule / duzenle.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});
  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  Map<String, String> _facts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final f = await memoryStore.all();
    if (!mounted) return;
    setState(() {
      _facts = f;
      _loading = false;
    });
  }

  Future<void> _addOrEdit({String? key, String? value}) async {
    final keyCtrl = TextEditingController(text: key ?? '');
    final valCtrl = TextEditingController(text: value ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(key == null ? 'Yeni bilgi' : 'Duzenle',
            style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyCtrl,
              enabled: key == null,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Anahtar (ornek: isim)'),
            ),
            TextField(
              controller: valCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Deger'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Vazgec')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok == true && keyCtrl.text.trim().isNotEmpty) {
      await memoryStore.remember(keyCtrl.text, valCtrl.text);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11111B),
        title: const Text('Hafiza'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addOrEdit(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _facts.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Hafiza bos.\nAjan seninle konustukca kalici bilgileri '
                      'buraya kaydeder; buradan da ekleyebilirsin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF6E6C8A)),
                    ),
                  ),
                )
              : ListView(
                  children: _facts.entries.map((e) {
                    return ListTile(
                      title: Text(e.key,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(e.value,
                          style: const TextStyle(color: Color(0xFF9E9CB8))),
                      onTap: () => _addOrEdit(key: e.key, value: e.value),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.redAccent),
                        onPressed: () async {
                          await memoryStore.forget(e.key);
                          await _refresh();
                        },
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}
