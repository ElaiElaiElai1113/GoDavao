import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../verify/data/verification_service.dart';

class AdminVerificationPage extends StatefulWidget {
  const AdminVerificationPage({super.key});

  @override
  State<AdminVerificationPage> createState() => _AdminVerificationPageState();
}

class _AdminVerificationPageState extends State<AdminVerificationPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = await VerificationService(supabase).adminListPending();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setStatus(String id, String status) async {
    String? reason;
    if (status == 'rejected') {
      reason = await showDialog<String?>(
        context: context,
        builder: (_) {
          final c = TextEditingController();
          return AlertDialog(
            title: const Text('Rejection reason'),
            content: TextField(
              controller: c,
              decoration: const InputDecoration(hintText: 'Optional reason'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, c.text.trim()),
                child: const Text('Submit'),
              ),
            ],
          );
        },
      );
    }
    await VerificationService(supabase).adminSetStatus(
      requestId: id,
      status: status,
      reason: reason?.isEmpty == true ? null : reason,
    );
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Marked $status.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification Requests')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    return ListTile(
                      title: Text('User: ${r['user_id']}'),
                      subtitle: Text('Requested: ${r['created_at']}'),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Reject'),
                            onPressed: () => _setStatus(r['id'], 'rejected'),
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.verified, size: 18),
                            label: const Text('Approve'),
                            onPressed: () => _setStatus(r['id'], 'approved'),
                          ),
                        ],
                      ),
                      onTap: () async {
                        // preview: sign URLs and show images
                        final svc = VerificationService(supabase);
                        final urls = <String>[];
                        for (final key in [
                          'selfie_url',
                          'id_front_url',
                          'id_back_url',
                        ]) {
                          final k = r[key] as String?;
                          if (k != null && k.isNotEmpty) {
                            urls.add(await svc.signUrl(k));
                          }
                        }
                        if (!context.mounted) return;
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder:
                              (_) => Padding(
                                padding: const EdgeInsets.all(12),
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                        'Preview',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ...urls.map(
                                        (u) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Image.network(
                                            u,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        );
                      },
                    );
                  },
                ),
              ),
    );
  }
}
