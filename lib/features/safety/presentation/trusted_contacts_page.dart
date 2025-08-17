import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/safety_service.dart';

class TrustedContactsPage extends StatefulWidget {
  const TrustedContactsPage({super.key});

  @override
  State<TrustedContactsPage> createState() => _TrustedContactsPageState();
}

class _TrustedContactsPageState extends State<TrustedContactsPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _sms = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _rows = await SafetyService(supabase).listContacts();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    if (_name.text.trim().isEmpty) return;
    await SafetyService(supabase).addContact(
      name: _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      sms: _sms,
    );
    _name.clear();
    _phone.clear();
    _sms = true;
    await _load();
  }

  Future<void> _delete(String id) async {
    await SafetyService(supabase).deleteContact(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trusted Contacts')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _name,
                            decoration: const InputDecoration(
                              labelText: 'Name',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone (SMS)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _sms,
                          onChanged: (v) => setState(() => _sms = v ?? true),
                        ),
                        const Text('Notify by SMS'),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.add),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        return ListTile(
                          title: Text(r['name'] ?? ''),
                          subtitle: Text(r['phone'] ?? ''),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(r['id']),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
    );
  }
}
