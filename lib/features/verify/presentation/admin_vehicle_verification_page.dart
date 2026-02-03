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
  static const _bg = Color(0xFFF7F7FB);
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  late final _VehicleAdminService svc;
  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  final _busy = <String>{};

  List<Map<String, dynamic>> _approved = [], _rejected = [];
  bool _loadingApproved = true, _loadingRejected = true;
  String _docFilter = 'all', _searchTerm = '';

  @override
  void initState() {
    super.initState();
    svc = _VehicleAdminService(Supabase.instance.client);
    _tabs = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(() {
      setState(() => _searchTerm = _searchCtrl.text.trim().toLowerCase());
    });
    _loadHistory('approved');
    _loadHistory('rejected');
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory(String status) async {
    if (status == 'approved') _loadingApproved = true;
    if (status == 'rejected') _loadingRejected = true;
    setState(() {});
    try {
      final data = await svc.fetch(status: status);
      if (status == 'approved') _approved = data;
      if (status == 'rejected') _rejected = data;
    } finally {
      if (!mounted) return;
      setState(() {
        if (status == 'approved') _loadingApproved = false;
        if (status == 'rejected') _loadingRejected = false;
      });
    }
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _approve(Map<String, dynamic> v) async {
    final id = '${v['id']}';
    final ok = await _confirm(
      'Approve vehicle?',
      'This will mark the vehicle as verified. Continue?',
      confirmText: 'Approve',
    );
    if (ok != true) return;

    setState(() => _busy.add(id));
    try {
      await svc.approve(id);
      _showSnack('Vehicle approved ✔');
      _loadHistory('approved');
    } catch (e) {
      _showSnack('Approve failed: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _reject(Map<String, dynamic> v) async {
    final id = '${v['id']}';
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
      _showSnack('Vehicle rejected ✖');
      _loadHistory('rejected');
    } catch (e) {
      _showSnack('Reject failed: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  bool _filterDocs(Map<String, dynamic> v) {
    final or = (v['or_key'] ?? '').toString().isNotEmpty;
    final cr = (v['cr_key'] ?? '').toString().isNotEmpty;
    return switch (_docFilter) {
      'complete' => or && cr,
      'missing' => !or || !cr,
      _ => true,
    };
  }

  bool _filterSearch(Map<String, dynamic> v) {
    if (_searchTerm.isEmpty) return true;
    final text = [
      v['plate'],
      v['make'],
      v['model'],
      v['color'],
      v['driver_name'],
      v['owner_name'],
      v['driver_id'],
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
    return text.contains(_searchTerm);
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> rows) =>
      rows.where((v) => _filterSearch(v) && _filterDocs(v)).toList();

  Future<bool?> _confirm(
    String title,
    String msg, {
    String confirmText = 'Confirm',
  }) {
    return showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(title),
            content: Text(msg),
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

  void _openPreview(Map<String, dynamic> v) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _VehiclePreviewSheet(vehicle: v, svc: svc),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(
      title: const Text('Vehicle Verification'),
      centerTitle: true,
      backgroundColor: _purple,
      foregroundColor: Colors.white,
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_purple, _purpleDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      bottom: TabBar(
        controller: _tabs,
        indicatorColor: Colors.white,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        tabs: const [
          Tab(text: 'Pending'),
          Tab(text: 'Approved'),
          Tab(text: 'Rejected'),
        ],
      ),
    ),
    body: Column(
      children: [
        _VehicleFilterPanel(
          controller: _searchCtrl,
          docFilter: _docFilter,
          onFilterChanged: (v) => setState(() => _docFilter = v),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _PendingVehicleTab(
                stream: svc.watchPending(),
                busy: _busy,
                applyFilters: _applyFilters,
                onPreview: _openPreview,
                onApprove: _approve,
                onReject: _reject,
              ),
              _VehicleHistoryTab(
                loading: _loadingApproved,
                items: _applyFilters(_approved),
                onRefresh: () => _loadHistory('approved'),
                stateLabel: 'Approved',
                accentColor: Colors.green.shade600,
              ),
              _VehicleHistoryTab(
                loading: _loadingRejected,
                items: _applyFilters(_rejected),
                onRefresh: () => _loadHistory('rejected'),
                stateLabel: 'Rejected',
                accentColor: Colors.red.shade600,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/* ------------------ SERVICE ------------------ */

class _VehicleAdminService {
  _VehicleAdminService(this.client);
  final SupabaseClient client;

  Stream<List<Map<String, dynamic>>> watchPending() => client
      .from('vehicles')
      .stream(primaryKey: ['id'])
      .eq('verification_status', 'pending')
      .map((rows) {
        final list = rows.map((e) => Map<String, dynamic>.from(e)).toList();
        list.sort((a, b) {
          final ad =
              DateTime.tryParse('${a['submitted_at']}') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bd =
              DateTime.tryParse('${b['submitted_at']}') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bd.compareTo(ad);
        });
        return list;
      });

  Future<List<Map<String, dynamic>>> fetch({required String status}) => client
      .from('vehicles')
      .select('*')
      .eq('verification_status', status)
      .order('reviewed_at', ascending: false);

  Future<void> approve(String id) => client
      .from('vehicles')
      .update({
        'verification_status': 'approved',
        'reviewed_by': client.auth.currentUser!.id,
        'reviewed_at': DateTime.now().toIso8601String(),
        'review_notes': null,
      })
      .eq('id', id);

  Future<void> reject(String id, {String? notes}) => client
      .from('vehicles')
      .update({
        'verification_status': 'rejected',
        'reviewed_by': client.auth.currentUser!.id,
        'reviewed_at': DateTime.now().toIso8601String(),
        if (notes != null) 'review_notes': notes,
      })
      .eq('id', id);

  Future<String?> signedUrl(String? key, {int expiresInSeconds = 300}) async {
    if (key == null || key.isEmpty) return null;
    return client.storage
        .from('verifications')
        .createSignedUrl(key, expiresInSeconds);
  }
}

/* ------------------ FILTER PANEL ------------------ */

class _VehicleFilterPanel extends StatelessWidget {
  const _VehicleFilterPanel({
    required this.controller,
    required this.docFilter,
    required this.onFilterChanged,
  });
  final TextEditingController controller;
  final String docFilter;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF7F7FB),
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Search plate, make, model, driver…',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final f in [
              ('all', Icons.inventory_2_outlined, 'All documents'),
              ('complete', Icons.check_circle_outline, 'Complete uploads'),
              ('missing', Icons.error_outline, 'Missing docs'),
            ])
              ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(f.$2, size: 16),
                    const SizedBox(width: 4),
                    Text(f.$3),
                  ],
                ),
                selected: docFilter == f.$1,
                onSelected: (_) => onFilterChanged(f.$1),
                selectedColor: const Color(0xFF6A27F7).withValues(alpha: .18),
                labelStyle: TextStyle(
                  color:
                      docFilter == f.$1
                          ? const Color(0xFF4B18C9)
                          : Colors.black87,
                  fontWeight:
                      docFilter == f.$1 ? FontWeight.w700 : FontWeight.w500,
                ),
                backgroundColor: Colors.white,
              ),
          ],
        ),
      ],
    ),
  );
}

/* ------------------ TABS, CARDS & DIALOGS ------------------ */

class _PendingVehicleTab extends StatelessWidget {
  const _PendingVehicleTab({
    required this.stream,
    required this.busy,
    required this.applyFilters,
    required this.onPreview,
    required this.onApprove,
    required this.onReject,
  });

  final Stream<List<Map<String, dynamic>>> stream;
  final Set<String> busy;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>>)
  applyFilters;
  final void Function(Map<String, dynamic>) onPreview;
  final void Function(Map<String, dynamic>) onApprove;
  final void Function(Map<String, dynamic>) onReject;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _VehicleErrorState(onRetry: () async {});
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final rows = applyFilters(snapshot.data ?? const []);
        if (rows.isEmpty) {
          return const _VehicleEmptyState(
            icon: Icons.directions_car_filled_outlined,
            message: 'No pending vehicles match your filters.',
          );
        }

        return RefreshIndicator(
          onRefresh: () async {},
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final row = rows[i];
              final isBusy = busy.contains('${row['id']}');
              return _PendingVehicleCard(
                vehicle: row,
                busy: isBusy,
                onPreview: () => onPreview(row),
                onApprove: () => onApprove(row),
                onReject: () => onReject(row),
              );
            },
          ),
        );
      },
    );
  }
}

class _VehicleHistoryTab extends StatelessWidget {
  const _VehicleHistoryTab({
    required this.loading,
    required this.items,
    required this.onRefresh,
    required this.stateLabel,
    required this.accentColor,
  });

  final bool loading;
  final List<Map<String, dynamic>> items;
  final Future<void> Function() onRefresh;
  final String stateLabel;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return _VehicleEmptyState(
        icon: stateLabel == 'Approved' ? Icons.verified : Icons.block,
        message: 'No $stateLabel vehicles yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: items.length,
        itemBuilder:
            (_, i) => _VehicleHistoryCard(
              vehicle: items[i],
              stateLabel: stateLabel,
              accentColor: accentColor,
            ),
      ),
    );
  }
}

/* ----- Compact Cards & Subwidgets ----- */

class _PendingVehicleCard extends StatelessWidget {
  const _PendingVehicleCard({
    required this.vehicle,
    required this.busy,
    required this.onPreview,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> vehicle;
  final bool busy;
  final VoidCallback onPreview;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final plate = (vehicle['plate'] ?? '—').toString();
    final make = (vehicle['make'] ?? '').toString();
    final model = (vehicle['model'] ?? '').toString();
    final driverName =
        (vehicle['driver_name'] ?? vehicle['owner_name'] ?? '—').toString();
    final submitted = DateTime.tryParse('${vehicle['submitted_at']}');
    final timeAgo = _relTime(submitted);
    final orKey = (vehicle['or_key'] ?? '').toString().isNotEmpty;
    final crKey = (vehicle['cr_key'] ?? '').toString().isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$plate • $make $model',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _VehicleTag(label: 'Pending', color: Colors.orange.shade600),
              ],
            ),
            const SizedBox(height: 4),
            Text('Driver: $driverName', style: _subStyle),
            Text('Submitted $timeAgo', style: _metaStyle),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _DocStatusChip(label: 'OR', available: orKey),
                _DocStatusChip(label: 'CR', available: crKey),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onPreview,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Preview'),
                ),
                const Spacer(),
                if (busy)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close, size: 18, color: Colors.red),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Approve'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static const _subStyle = TextStyle(fontSize: 12.5, color: Colors.black54);
  static const _metaStyle = TextStyle(fontSize: 12, color: Colors.black45);

  static String _relTime(DateTime? dt) {
    if (dt == null) return '—';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }
}

class _VehicleHistoryCard extends StatelessWidget {
  const _VehicleHistoryCard({
    required this.vehicle,
    required this.stateLabel,
    required this.accentColor,
  });
  final Map<String, dynamic> vehicle;
  final String stateLabel;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final plate = (vehicle['plate'] ?? '—').toString();
    final make = (vehicle['make'] ?? '').toString();
    final model = (vehicle['model'] ?? '').toString();
    final reviewed = DateTime.tryParse(
      '${vehicle['reviewed_at'] ?? vehicle['updated_at']}',
    );
    final notes = (vehicle['review_notes'] ?? '').toString().trim();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$plate • $make $model',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _VehicleTag(label: stateLabel, color: accentColor),
              ],
            ),
            const SizedBox(height: 4),
            Text('Reviewed: ${reviewed ?? '—'}', style: _metaStyle),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                notes,
                style: const TextStyle(fontSize: 12.5, color: Colors.black87),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const _metaStyle = TextStyle(fontSize: 12, color: Colors.black54);
}

class _VehicleTag extends StatelessWidget {
  const _VehicleTag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

class _DocStatusChip extends StatelessWidget {
  const _DocStatusChip({required this.label, required this.available});
  final String label;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final color = available ? Colors.green.shade600 : Colors.orange.shade700;
    final bg = available ? Colors.green.shade50 : Colors.orange.shade50;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            available ? Icons.check_circle : Icons.error_outline,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleEmptyState extends StatelessWidget {
  const _VehicleEmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: Colors.black26),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    ),
  );
}

class _VehicleErrorState extends StatelessWidget {
  const _VehicleErrorState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 42, color: Colors.redAccent),
        const SizedBox(height: 10),
        const Text(
          'Failed to load vehicles. Try again.',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

/* ------------------ PREVIEW & DIALOG ------------------ */

class _VehiclePreviewSheet extends StatefulWidget {
  const _VehiclePreviewSheet({required this.vehicle, required this.svc});
  final Map<String, dynamic> vehicle;
  final _VehicleAdminService svc;

  @override
  State<_VehiclePreviewSheet> createState() => _VehiclePreviewSheetState();
}

class _VehiclePreviewSheetState extends State<_VehiclePreviewSheet> {
  String? _signedOr, _signedCr;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final or = widget.vehicle['or_key'] as String?;
    final cr = widget.vehicle['cr_key'] as String?;
    _load(or, cr);
  }

  Future<void> _load(String? or, String? cr) async {
    setState(() => _loading = true);
    _signedOr = await widget.svc.signedUrl(or);
    _signedCr = await widget.svc.signedUrl(cr);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    final orAvailable = (v['or_key'] ?? '').toString().isNotEmpty;
    final crAvailable = (v['cr_key'] ?? '').toString().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${v['plate'] ?? '—'} • ${v['make'] ?? ''} ${v['model'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _DocStatusChip(label: 'OR', available: orAvailable),
                _DocStatusChip(label: 'CR', available: crAvailable),
              ],
            ),
            const Divider(height: 20),
            const Text(
              'Documents',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            if (_loading)
              const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _buildImage('Official Receipt (OR)', _signedOr),
              const SizedBox(height: 10),
              _buildImage('Certificate of Registration (CR)', _signedCr),
            ],
            const SizedBox(height: 10),
            if ((v['review_notes'] ?? '').toString().isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Notes',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    v['review_notes'] as String? ?? '',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String title, String? url) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      if (url == null)
        const Text(
          'No file uploaded',
          style: TextStyle(color: Colors.black54, fontSize: 12),
        )
      else
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(url, height: 200, fit: BoxFit.cover),
        ),
    ],
  );
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _ctrl,
      decoration: const InputDecoration(
        labelText: 'Notes (optional)',
        hintText: 'Reason for rejection…',
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
