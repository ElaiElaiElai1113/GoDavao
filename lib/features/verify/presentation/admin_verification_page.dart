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
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Verification Review'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Approved'),
              Tab(text: 'Rejected'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildList(admin.watchPending()),
            _buildList(admin.watchApproved()),
            _buildList(admin.watchRejected()),
          ],
        ),
      ),
    );
  }

  Widget _buildList(Stream<List<Map<String, dynamic>>> stream) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (items.isEmpty) {
          return const Center(child: Text('No records found'));
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final r = items[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    r['role'] == 'driver' ? Colors.green : Colors.purple,
                child: Text(
                  r['role'].substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(r['name'] ?? r['user_id']),
              subtitle: Text(
                '${r['role']} • Submitted ${DateTime.parse(r['created_at']).toLocal()}',
              ),
              trailing:
                  r['status'] == 'pending'
                      ? Wrap(
                        spacing: 8,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            tooltip: 'Reject',
                            onPressed:
                                () => admin.reject(r['id'], notes: 'Not clear'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            tooltip: 'Approve',
                            onPressed: () => admin.approve(r['id']),
                          ),
                        ],
                      )
                      : Text(
                        r['status'].toUpperCase(),
                        style: TextStyle(
                          color:
                              r['status'] == 'approved'
                                  ? Colors.green
                                  : Colors.red,
                        ),
                      ),
              onTap: () => _open(context, r),
            );
          },
        );
      },
    );
  }

  void _open(BuildContext context, Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (_) => Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'User: ${r['user_id']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
                  if (r['status'] == 'pending')
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              _showRejectDialog(r['id']);
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

  void _showRejectDialog(String requestId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Reject Verification'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Reason for rejection',
                hintText: 'e.g. ID is blurry, please re-upload',
              ),
              maxLines: 3,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context); // close dialog
                  await admin.reject(requestId, notes: controller.text.trim());
                },
                child: const Text('Reject'),
              ),
            ],
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
              child: Image.network(
                url,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Container(
                    height: 180,
                    color: Colors.grey[200],
                    child: const Center(child: Text('Image not available')),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
  }
}
