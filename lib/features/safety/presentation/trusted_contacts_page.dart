import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/trusted_contacts_service.dart';
import '../models/trusted_contact.dart';

class TrustedContactsPage extends StatefulWidget {
  const TrustedContactsPage({super.key});
  @override
  State<TrustedContactsPage> createState() => _TrustedContactsPageState();
}

class _TrustedContactsPageState extends State<TrustedContactsPage> {
  late final TrustedContactsService _svc;
  List<TrustedContact> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _svc = TrustedContactsService(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _svc.listMine();
      if (mounted) setState(() => _items = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load contacts: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({TrustedContact? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(
              existing == null ? 'Add Trusted Contact' : 'Edit Trusted Contact',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email (optional)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (ok != true) return;

    try {
      if (existing == null) {
        await _svc.add(
          name: nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim(),
          email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
        );
      } else {
        await _svc.update(
          existing.id,
          name: nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim(),
          email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  Future<void> _delete(TrustedContact c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Remove contact?'),
            content: Text('Remove ${c.name} from your trusted contacts?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
    );
    if (ok == true) {
      await _svc.remove(c.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trusted Contacts')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
              ? const Center(
                child: Text(
                  'No trusted contacts yet.\nAdd one to share your location during emergencies.',
                  textAlign: TextAlign.center,
                ),
              )
              : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemBuilder: (_, i) {
                  final c = _items[i];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(c.name),
                    subtitle: Text(
                      [c.phone, if (c.email != null) c.email!].join(' · '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _openForm(existing: c),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _delete(c),
                        ),
                      ],
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Contact'),
      ),
    );
  }
}
