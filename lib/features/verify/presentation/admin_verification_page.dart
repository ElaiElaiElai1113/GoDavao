import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/admin_service.dart';

class AdminVerificationPage extends StatefulWidget {
  const AdminVerificationPage({super.key});

  @override
  State<AdminVerificationPage> createState() => _AdminVerificationPageState();
}

class _AdminVerificationPageState extends State<AdminVerificationPage>
    with SingleTickerProviderStateMixin {
  late final AdminVerificationService admin;
  late final TabController _tabs;

  // per-row busy state while approving/rejecting
  final Set<String> _busyIds = {};

  // cached lists for Approved / Rejected tabs
  List<Map<String, dynamic>> _approved = [];
  List<Map<String, dynamic>> _rejected = [];
  bool _loadingApproved = true;
  bool _loadingRejected = true;

  @override
  void initState() {
    super.initState();
    admin = AdminVerificationService(Supabase.instance.client);
    _tabs = TabController(length: 3, vsync: this);
    _loadApproved();
    _loadRejected();
  }

  Future<void> _loadApproved() async {
    setState(() => _loadingApproved = true);
    try {
      _approved = await admin.fetch(status: 'approved');
    } catch (_) {
      // swallow; we show snack on action errors only
    } finally {
      if (mounted) setState(() => _loadingApproved = false);
    }
  }

  Future<void> _loadRejected() async {
    setState(() => _loadingRejected = true);
    try {
      _rejected = await admin.fetch(status: 'rejected');
    } catch (_) {
      // swallow
    } finally {
      if (mounted) setState(() => _loadingRejected = false);
    }
  }

  Future<void> _handleApprove(Map<String, dynamic> row) async {
    final id = row['id'].toString();
    final confirm = await _confirm(
      title: 'Approve verification?',
      message:
          'This will mark the user as verified for the requested role. Continue?',
      confirmText: 'Approve',
    );
    if (confirm != true) return;

    setState(() => _busyIds.add(id));
    try {
      await admin.approve(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Approved ✔')));
      // pending stream auto-removes item; refresh approved tab
      _loadApproved();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Approve failed: $e')));
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _handleReject(Map<String, dynamic> row) async {
    final id = row['id'].toString();

    String? notes;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => _ReasonDialog(
            title: 'Reject verification?',
            onSubmit: (s) => notes = s,
          ),
    );
    if (ok != true) return;

    setState(() => _busyIds.add(id));
    try {
      await admin.reject(
        id,
        notes: notes?.trim().isEmpty == true ? null : notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rejected ✖')));
      // pending stream auto-removes item; refresh rejected tab
      _loadRejected();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reject failed: $e')));
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    String confirmText = 'Confirm',
  }) {
    return showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmText),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification Review'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Rejected'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // PENDING — realtime
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: admin.watchPending(), // ensure service adds .select('*')
            builder: (context, snap) {
              final items = snap.data ?? const [];
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (items.isEmpty) {
                return const _EmptyState(
                  icon: Icons.verified_user_outlined,
                  text: 'No pending requests',
                );
              }
              return RefreshIndicator(
                onRefresh: () async {}, // stream will refresh automatically
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder:
                      (_, i) => _RequestTile(
                        row: items[i],
                        busy: _busyIds.contains(items[i]['id'].toString()),
                        onOpen: () => _openPreview(items[i]),
                        onApprove: () => _handleApprove(items[i]),
                        onReject: () => _handleReject(items[i]),
                      ),
                ),
              );
            },
          ),

          // APPROVED — pull to refresh
          _ListWithRefresh(
            loading: _loadingApproved,
            items: _approved,
            onRefresh: _loadApproved,
            emptyIcon: Icons.verified,
            emptyText: 'No approved requests yet',
            buildTile: (r) => _HistoryTile(row: r, color: Colors.green),
            onOpen: _openPreview,
          ),

          // REJECTED — pull to refresh
          _ListWithRefresh(
            loading: _loadingRejected,
            items: _rejected,
            onRefresh: _loadRejected,
            emptyIcon: Icons.block,
            emptyText: 'No rejected requests',
            buildTile: (r) => _HistoryTile(row: r, color: Colors.red),
            onOpen: _openPreview,
          ),
        ],
      ),
    );
  }

  void _openPreview(Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PreviewSheet(row: r),
    );
  }
}

/* ---------- Widgets ---------- */

class _RequestTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _RequestTile({
    required this.row,
    required this.busy,
    required this.onOpen,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final id = row['id'].toString();
    final userId = row['user_id']?.toString() ?? '—';
    final role = (row['role'] ?? '—').toString();
    final createdAt = DateTime.tryParse('${row['created_at']}')?.toLocal();

    return ListTile(
      title: Text('$role – ${userId.substring(0, 8)}'),
      subtitle: Text(createdAt == null ? 'Submitted' : 'Submitted $createdAt'),
      onTap: onOpen,
      trailing:
          busy
              ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : Wrap(
                spacing: 6,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    tooltip: 'Reject',
                    onPressed: onReject,
                  ),
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    tooltip: 'Approve',
                    onPressed: onApprove,
                  ),
                ],
              ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final Color color;
  const _HistoryTile({required this.row, required this.color});

  @override
  Widget build(BuildContext context) {
    final userId = row['user_id']?.toString() ?? '—';
    final role = (row['role'] ?? '—').toString();
    final reviewedAt = DateTime.tryParse('${row['reviewed_at']}')?.toLocal();
    final status = (row['status'] ?? '').toString().toUpperCase();

    return ListTile(
      leading: Icon(
        status == 'APPROVED' ? Icons.verified : Icons.block,
        color: color,
      ),
      title: Text('$role – ${userId.substring(0, 8)}'),
      subtitle: Text(reviewedAt == null ? status : '$status on $reviewedAt'),
    );
  }
}

class _ListWithRefresh extends StatelessWidget {
  final bool loading;
  final List<Map<String, dynamic>> items;
  final Future<void> Function() onRefresh;
  final IconData emptyIcon;
  final String emptyText;
  final Widget Function(Map<String, dynamic>) buildTile;
  final void Function(Map<String, dynamic>) onOpen;

  const _ListWithRefresh({
    required this.loading,
    required this.items,
    required this.onRefresh,
    required this.emptyIcon,
    required this.emptyText,
    required this.buildTile,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return _EmptyState(icon: emptyIcon, text: emptyText);
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder:
            (_, i) => InkWell(
              onTap: () => onOpen(items[i]),
              child: buildTile(items[i]),
            ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: Colors.black26),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({required this.row});
  final Map<String, dynamic> row;

  String? _key(Map r, String k) =>
      (r[k] as String?)?.isNotEmpty == true ? r[k] as String : null;

  @override
  Widget build(BuildContext context) {
    final sb = Supabase.instance.client;
    String? urlOf(String? key) =>
        key == null ? null : sb.storage.from('verifications').getPublicUrl(key);

    final idFront = _key(row, 'id_front_key');
    final idBack = _key(row, 'id_back_key');
    final selfie = _key(row, 'selfie_key');
    final dl = _key(row, 'driver_license_key');
    final orcr = _key(row, 'orcr_key');

    Widget section(String title, String? key) {
      if (key == null) return const SizedBox.shrink();
      final url = urlOf(key);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(url!, height: 160, fit: BoxFit.cover),
          ),
          const SizedBox(height: 12),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('User: ${row['user_id']}'),
            const SizedBox(height: 6),
            Text('Role: ${row['role']}'),
            const Divider(height: 20),
            section('ID Front', idFront),
            section('ID Back', idBack),
            section('Selfie', selfie),
            section('Driver License', dl),
            section('OR/CR', orcr),
          ],
        ),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  final String title;
  final void Function(String notes) onSubmit;
  const _ReasonDialog({required this.title, required this.onSubmit});

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        decoration: const InputDecoration(
          labelText: 'Notes (optional)',
          hintText: 'Tell the user why this was rejected',
        ),
        maxLines: 3,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _sending
                  ? null
                  : () async {
                    setState(() => _sending = true);
                    widget.onSubmit(_ctrl.text);
                    if (mounted) Navigator.pop(context, true);
                  },
          child:
              _sending
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('Reject'),
        ),
      ],
    );
  }
}
