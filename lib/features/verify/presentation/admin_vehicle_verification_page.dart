import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminVehicleVerificationPage extends StatefulWidget {
  const AdminVehicleVerificationPage({super.key});

  @override
  State<AdminVehicleVerificationPage> createState() =>
      _AdminVehicleVerificationPageState();
}

class _AdminVehicleVerificationPageState
    extends State<AdminVehicleVerificationPage>
    with SingleTickerProviderStateMixin {
  late final _VehicleAdminService svc;
  late final TabController _tabs;

  // Optimistic/busy per-row ids
  final Set<String> _busy = {};

  // Caches for approved/rejected lists
  List<Map<String, dynamic>> _approved = [];
  List<Map<String, dynamic>> _rejected = [];
  bool _loadingApproved = true;
  bool _loadingRejected = true;

  @override
  void initState() {
    super.initState();
    svc = _VehicleAdminService(Supabase.instance.client);
    _tabs = TabController(length: 3, vsync: this);
    _loadApproved();
    _loadRejected();
  }

  Future<void> _loadApproved() async {
    setState(() => _loadingApproved = true);
    try {
      _approved = await svc.fetch(status: 'approved');
    } catch (_) {
      // ignore; show toasts only on action
    } finally {
      if (mounted) setState(() => _loadingApproved = false);
    }
  }

  Future<void> _loadRejected() async {
    setState(() => _loadingRejected = true);
    try {
      _rejected = await svc.fetch(status: 'rejected');
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingRejected = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> v) async {
    final id = v['id'].toString();
    final ok = await _confirm(
      'Approve vehicle?',
      'This will mark the vehicle as verified. Continue?',
      confirmText: 'Approve',
    );
    if (ok != true) return;

    setState(() => _busy.add(id));
    try {
      await svc.approve(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vehicle approved ✔')));
      // pending stream will drop item automatically, refresh approved tab
      _loadApproved();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Approve failed: $e')));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _reject(Map<String, dynamic> v) async {
    final id = v['id'].toString();
    String? notes;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => _ReasonDialog(
            title: 'Reject vehicle?',
            onSubmit: (s) => notes = s,
          ),
    );
    if (ok != true) return;

    setState(() => _busy.add(id));
    try {
      await svc.reject(id, notes: notes?.trim().isEmpty == true ? null : notes);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vehicle rejected ✖')));
      _loadRejected();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reject failed: $e')));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<bool?> _confirm(
    String title,
    String message, {
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

  void _openPreview(Map<String, dynamic> v) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VehiclePreviewSheet(vehicle: v, svc: svc),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Verification'),
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
          // PENDING (realtime)
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: svc.watchPending(),
            builder: (context, snap) {
              final items = snap.data ?? const [];
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (items.isEmpty) {
                return const _EmptyState(
                  icon: Icons.directions_car_filled_outlined,
                  text: 'No pending vehicles',
                );
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final v = items[i];
                  final busy = _busy.contains(v['id'].toString());
                  return _PendingTile(
                    v: v,
                    busy: busy,
                    onOpen: () => _openPreview(v),
                    onApprove: () => _approve(v),
                    onReject: () => _reject(v),
                  );
                },
              );
            },
          ),

          // APPROVED
          _ListWithRefresh(
            loading: _loadingApproved,
            items: _approved,
            onRefresh: _loadApproved,
            emptyIcon: Icons.verified,
            emptyText: 'No approved vehicles',
            buildTile:
                (v) => _HistoryTile(
                  v: v,
                  icon: Icons.verified,
                  color: Colors.green,
                ),
            onOpen: _openPreview,
          ),

          // REJECTED
          _ListWithRefresh(
            loading: _loadingRejected,
            items: _rejected,
            onRefresh: _loadRejected,
            emptyIcon: Icons.block,
            emptyText: 'No rejected vehicles',
            buildTile:
                (v) => _HistoryTile(v: v, icon: Icons.block, color: Colors.red),
            onOpen: _openPreview,
          ),
        ],
      ),
    );
  }
}

/* ================== SERVICE ================== */

class _VehicleAdminService {
  _VehicleAdminService(this.client);
  final SupabaseClient client;

  // ✅ Realtime pending list (no .select on streams; sort client-side)
  // in _VehicleAdminService
  Stream<List<Map<String, dynamic>>> watchPending() {
    final s = client
        .from('vehicles')
        .stream(primaryKey: ['id'])
        .eq('verification_status', 'pending');

    return s.map((rows) {
      final list =
          rows
              .map((e) => Map<String, dynamic>.from(e as Map))
              // optional: only show vehicles that uploaded OR/CR
              .where((v) => (v['orcr_key'] as String?)?.isNotEmpty == true)
              .toList();

      list.sort((a, b) {
        final ad =
            DateTime.tryParse('${a['submitted_at']}') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bd =
            DateTime.tryParse('${b['submitted_at']}') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad); // newest first
      });
      return list;
    });
  }

  // Pull lists for history tabs
  Future<List<Map<String, dynamic>>> fetch({required String status}) async {
    return await client
        .from('vehicles')
        .select('*')
        .eq('verification_status', status)
        .order('reviewed_at', ascending: false);
  }

  Future<void> approve(String vehicleId) async {
    await client
        .from('vehicles')
        .update({
          'verification_status': 'approved',
          'reviewed_by': client.auth.currentUser!.id,
          'reviewed_at': DateTime.now().toIso8601String(),
          'review_notes': null,
        })
        .eq('id', vehicleId);
  }

  Future<void> reject(String vehicleId, {String? notes}) async {
    await client
        .from('vehicles')
        .update({
          'verification_status': 'rejected',
          'reviewed_by': client.auth.currentUser!.id,
          'reviewed_at': DateTime.now().toIso8601String(),
          if (notes != null) 'review_notes': notes,
        })
        .eq('id', vehicleId);
  }

  // Signed URL for private bucket objects
  Future<String?> signedUrl(
    String? storageKey, {
    int expiresInSeconds = 300,
  }) async {
    if (storageKey == null || storageKey.isEmpty) return null;
    final res = await client.storage
        .from('verifications')
        .createSignedUrl(storageKey, expiresInSeconds);
    return res;
  }
}

/* ================== WIDGETS ================== */

class _PendingTile extends StatelessWidget {
  const _PendingTile({
    required this.v,
    required this.busy,
    required this.onOpen,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> v;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final id = v['id'].toString();
    final plate = (v['plate'] ?? '').toString();
    final make = (v['make'] ?? '').toString();
    final model = (v['model'] ?? '').toString();
    final created = DateTime.tryParse('${v['submitted_at']}')?.toLocal();

    return ListTile(
      title: Text('$plate • $make $model'),
      subtitle: Text(created == null ? 'Submitted' : 'Submitted $created'),
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
  const _HistoryTile({
    required this.v,
    required this.icon,
    required this.color,
  });

  final Map<String, dynamic> v;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final plate = (v['plate'] ?? '').toString();
    final make = (v['make'] ?? '').toString();
    final model = (v['model'] ?? '').toString();
    final reviewed = DateTime.tryParse('${v['reviewed_at']}')?.toLocal();
    final status = (v['verification_status'] ?? '').toString().toUpperCase();

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text('$plate • $make $model'),
      subtitle: Text(reviewed == null ? status : '$status on $reviewed'),
    );
  }
}

class _ListWithRefresh extends StatelessWidget {
  const _ListWithRefresh({
    required this.loading,
    required this.items,
    required this.onRefresh,
    required this.emptyIcon,
    required this.emptyText,
    required this.buildTile,
    required this.onOpen,
  });

  final bool loading;
  final List<Map<String, dynamic>> items;
  final Future<void> Function() onRefresh;
  final IconData emptyIcon;
  final String emptyText;
  final Widget Function(Map<String, dynamic>) buildTile;
  final void Function(Map<String, dynamic>) onOpen;

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
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

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

class _VehiclePreviewSheet extends StatefulWidget {
  const _VehiclePreviewSheet({
    required this.vehicle,
    required this.svc,
    super.key,
  });
  final Map<String, dynamic> vehicle;
  final _VehicleAdminService svc;

  @override
  State<_VehiclePreviewSheet> createState() => _VehiclePreviewSheetState();
}

class _VehiclePreviewSheetState extends State<_VehiclePreviewSheet> {
  String? _signedUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final key = (widget.vehicle['orcr_key'] as String?);
    _load(key);
  }

  Future<void> _load(String? key) async {
    setState(() => _loading = true);
    try {
      _signedUrl = await widget.svc.signedUrl(key, expiresInSeconds: 300);
    } catch (_) {
      _signedUrl = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vehicle', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '${v['plate'] ?? '—'} • ${v['make'] ?? ''} ${v['model'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Color: ${v['color'] ?? '—'} — Seats: ${v['seats'] ?? '—'}'),
            const Divider(height: 20),
            const Text(
              'OR/CR Document',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_signedUrl == null)
              const Text('No document uploaded')
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _signedUrl!,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 12),
            if (v['review_notes'] != null &&
                (v['review_notes'] as String).isNotEmpty) ...[
              const Text(
                'Notes',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(v['review_notes'] as String),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.onSubmit});

  final String title;
  final void Function(String notes) onSubmit;

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
          hintText: 'Why is this being rejected?',
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
