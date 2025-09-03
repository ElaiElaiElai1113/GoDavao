import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/admin_service.dart';

class AdminVerificationPage extends StatefulWidget {
  const AdminVerificationPage({super.key});

  @override
  State<AdminVerificationPage> createState() => _AdminVerificationPageState();
}

class _AdminVerificationPageState extends State<AdminVerificationPage> {
  late final AdminVerificationService admin;

  @override
  void initState() {
    super.initState();
    admin = AdminVerificationService(Supabase.instance.client);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification Review')),
      body: StreamBuilder(
        stream: admin.watchPending(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('No pending requests'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = items[i];
              return ListTile(
                title: Text(
                  '${r['role']} – ${r['user_id'].toString().substring(0, 8)}',
                ),
                subtitle: Text(
                  'Submitted ${DateTime.parse(r['created_at']).toLocal()}',
                ),
                onTap: () => _open(context, r),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed:
                          () => admin.reject(r['id'], notes: 'Not clear'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: () => admin.approve(r['id']),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _open(BuildContext context, Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (_) => Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('User: ${r['user_id']}'),
                  const SizedBox(height: 8),
                  Text('Role: ${r['role']}'),
                  const Divider(),
                  _preview('ID Front', r['id_front_url']),
                  _preview('ID Back', r['id_back_url']),
                  _preview('Selfie', r['selfie_url']),
                  if (r['driver_license_url'] != null)
                    _preview('License', r['driver_license_url']),
                  if (r['orcr_url'] != null) _preview('OR/CR', r['orcr_url']),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            admin.reject(r['id'], notes: 'Invalid');
                          },
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(context);
                            admin.approve(r['id']);
                          },
                          child: const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _preview(String label, String? url) {
    return url == null
        ? const SizedBox.shrink()
        : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(url, height: 160, fit: BoxFit.cover),
            ),
            const SizedBox(height: 12),
          ],
        );
  }
}
