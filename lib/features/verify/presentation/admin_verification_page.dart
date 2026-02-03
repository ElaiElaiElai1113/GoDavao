import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/admin_service.dart';

String getPublicUrl(String key) {
  if (key.isEmpty) return '';
  final supabase = Supabase.instance.client;
  return supabase.storage.from('verifications').getPublicUrl(key);
}

class AdminVerificationPage extends StatefulWidget {
  const AdminVerificationPage({super.key});
  @override
  State<AdminVerificationPage> createState() => _AdminVerificationPageState();
}

class _AdminVerificationPageState extends State<AdminVerificationPage>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFFF7F7FB);
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  final _tsFmt = DateFormat('MMM d, yyyy • h:mm a');

  late final AdminVerificationService admin;
  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  final _busyIds = <String>{};

  List<Map<String, dynamic>> _approved = [];
  List<Map<String, dynamic>> _rejected = [];
  bool _loadingApproved = true, _loadingRejected = true;
  String _roleFilter = 'all', _query = '';

  @override
  void initState() {
    super.initState();
    admin = AdminVerificationService(Supabase.instance.client);
    _tabs = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
    _loadHistory('approved');
    _loadHistory('rejected');
  }

  Future<void> _loadHistory(String status) async {
    setState(() {
      if (status == 'approved') {
        _loadingApproved = true;
      } else {
        _loadingRejected = true;
      }
    });
    try {
      final res = await Supabase.instance.client
          .from('users')
          .select(
            'id, name, role, verified_role, phone, verification_status, updated_at',
          )
          .eq('verification_status', status)
          .order('updated_at', ascending: false);
      setState(() {
        if (status == 'approved') {
          _approved = List<Map<String, dynamic>>.from(res);
        } else {
          _rejected = List<Map<String, dynamic>>.from(res);
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          if (status == 'approved') {
            _loadingApproved = false;
          } else {
            _loadingRejected = false;
          }
        });
      }
    }
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows) {
    return rows.where((r) {
      final role = (r['role'] ?? '').toString().toLowerCase();
      final matchesRole = _roleFilter == 'all' || _roleFilter == role;
      if (!matchesRole) return false;
      if (_query.isEmpty) return true;
      final text = '${r['id']} ${r['name']} ${r['phone']}'.toLowerCase();
      return text.contains(_query);
    }).toList();
  }

  String _fmt(dynamic v) {
    final d = v == null ? null : DateTime.tryParse(v.toString());
    return d == null ? '—' : _tsFmt.format(d.toLocal());
  }

  Color _roleColor(String r) =>
      {'driver': Colors.orange.shade600, 'passenger': Colors.blue.shade600}[r
          .toLowerCase()] ??
      Colors.grey.shade600;

  Future<void> _approve(Map r) async {
    final ok = await _confirm(
      'Approve verification?',
      'Mark this user as verified?',
    );
    if (ok != true) return;
    final id = r['id'].toString();
    setState(() => _busyIds.add(id));
    try {
      await admin.approve(id);
      _loadHistory('approved');
      if (mounted) _toast('Approved ✔');
    } catch (e) {
      _toast('Approve failed: $e');
    } finally {
      setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _reject(Map r) async {
    final notes = await _inputDialog(
      'Reject verification?',
      'Reason (optional)',
    );
    if (notes == null) return;
    final id = r['id'].toString();
    setState(() => _busyIds.add(id));
    try {
      await admin.reject(id, notes: notes);
      _loadHistory('rejected');
      if (mounted) _toast('Rejected ✖');
    } catch (e) {
      _toast('Reject failed: $e');
    } finally {
      setState(() => _busyIds.remove(id));
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<bool?> _confirm(String title, String msg) => showDialog<bool>(
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
              child: const Text('Approve'),
            ),
          ],
        ),
  );

  Future<String?> _inputDialog(String title, String hint) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: ctrl,
              decoration: InputDecoration(hintText: hint),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, ctrl.text),
                child: const Text('Reject'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(
      title: const Text('Verification Review'),
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
        _FilterPanel(
          controller: _searchCtrl,
          roleFilter: _roleFilter,
          onRoleChanged: (r) => setState(() => _roleFilter = r),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _VerificationTab(
                stream: admin.watchPending(),
                busyIds: _busyIds,
                label: 'Pending',
                onApprove: _approve,
                onReject: _reject,
                roleColor: _roleColor,
                format: _fmt,
                displayName: (r) => r['name'] as String? ?? 'Unknown',
                filter: _filter,
              ),
              _VerificationTab.static(
                loading: _loadingApproved,
                data: _filter(_approved),
                label: 'Approved',
                color: Colors.green.shade600,
                onRefresh: () => _loadHistory('approved'),
                format: _fmt,
                roleColor: _roleColor,
                displayName: (r) => r['name'] as String? ?? 'Unknown',
              ),
              _VerificationTab.static(
                loading: _loadingRejected,
                data: _filter(_rejected),
                label: 'Rejected',
                color: Colors.red.shade600,
                onRefresh: () => _loadHistory('rejected'),
                format: _fmt,
                roleColor: _roleColor,
                displayName: (r) => r['name'] as String? ?? 'Unknown',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/* ---------- Reusable Widgets ---------- */

class _VerificationTab extends StatelessWidget {
  const _VerificationTab({
    this.stream,
    this.data,
    this.loading = false,
    required this.label,
    this.color,
    this.onApprove,
    this.onReject,
    this.onRefresh,
    required this.roleColor,
    required this.format,
    required this.displayName,
    this.busyIds = const {},
    this.filter,
  });

  final Stream<List<Map<String, dynamic>>>? stream;
  final List<Map<String, dynamic>>? data;
  final bool loading;
  final String label;
  final Color? color;
  final Future<void> Function()? onRefresh;
  final void Function(Map<String, dynamic>)? onApprove, onReject;
  final Color Function(String) roleColor;
  final String Function(dynamic) format;
  final String Function(Map<String, dynamic>) displayName;
  final Set<String> busyIds;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>>)? filter;

  factory _VerificationTab.static({
    required bool loading,
    required List<Map<String, dynamic>> data,
    required String label,
    required Color color,
    required Future<void> Function() onRefresh,
    required String Function(dynamic) format,
    required Color Function(String) roleColor,
    required String Function(Map<String, dynamic>) displayName,
  }) => _VerificationTab(
    data: data,
    loading: loading,
    label: label,
    color: color,
    onRefresh: onRefresh,
    roleColor: roleColor,
    format: format,
    displayName: displayName,
  );

  @override
  Widget build(BuildContext context) {
    if (stream != null) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return _StateMessage(
              icon: Icons.error,
              text: 'Error loading data.',
            );
          }
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = filter!(snap.data ?? []);
          return _list(rows);
        },
      );
    }

    if (loading) return const Center(child: CircularProgressIndicator());
    if (data!.isEmpty) {
      return _StateMessage(
        icon: Icons.inbox_outlined,
        text: 'No $label records found.',
      );
    }
    return RefreshIndicator(onRefresh: onRefresh!, child: _list(data!));
  }

  Widget _list(List<Map<String, dynamic>> rows) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
    itemCount: rows.length,
    itemBuilder: (_, i) {
      final r = rows[i];
      return _VerificationCard(
        row: r,
        roleColor: roleColor,
        format: format,
        displayName: displayName,
        color: color,
        busy: busyIds.contains(r['id'].toString()),
        onApprove: onApprove != null ? () => onApprove!(r) : null,
        onReject: onReject != null ? () => onReject!(r) : null,
      );
    },
  );
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.row,
    required this.roleColor,
    required this.format,
    required this.displayName,
    this.color,
    this.busy = false,
    this.onApprove,
    this.onReject,
  });
  final Map<String, dynamic> row;
  final Color Function(String) roleColor;
  final String Function(dynamic) format;
  final String Function(Map<String, dynamic>) displayName;
  final Color? color;
  final bool busy;
  final VoidCallback? onApprove, onReject;

  @override
  Widget build(BuildContext context) {
    final name = displayName(row);
    final role = (row['role'] ?? '—').toString();
    final reviewed = format(
      row['verification_reviewed_at'] ?? row['updated_at'],
    );
    final notes = (row['verification_notes'] ?? '').toString().trim();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (row['phone'] != null && row['phone'] != '—')
                        Text(
                          row['phone'] as String,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ),

                _Tag(role.toUpperCase(), roleColor(role)),
                if (color != null) ...[
                  const SizedBox(width: 6),
                  _Tag(row['verification_status'] as String? ?? '', color!),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Reviewed: $reviewed',
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            if (notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  notes,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black87),
                ),
              ),
            // --- Verification images (Pending only) ---
            if (onApprove != null && onReject != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _idImageBox(row['id_front_key'], 'Front ID'),
                  _idImageBox(row['id_back_key'], 'Back ID'),
                  _idImageBox(row['selfie_key'], 'Selfie'),
                ],
              ),
            ],

            if (onApprove != null || onReject != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    if (busy)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else ...[
                      OutlinedButton.icon(
                        onPressed: onReject,
                        icon: const Icon(Icons.close, color: Colors.red),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
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
              ),
          ],
        ),
      ),
    );
  }
}

Widget _idImageBox(dynamic key, String label) {
  final keyStr = key?.toString() ?? '';
  if (keyStr.isEmpty) {
    return Container(
      width: 100,
      height: 100,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.image_not_supported, color: Colors.grey),
    );
  }

  final supabase = Supabase.instance.client;
  final url = supabase.storage.from('verifications').getPublicUrl(keyStr);

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: 100,
          height: 100,
          fit: BoxFit.cover,
          errorBuilder:
              (_, __, ___) =>
                  const Icon(Icons.broken_image, size: 40, color: Colors.grey),
        ),
      ),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.controller,
    required this.roleFilter,
    required this.onRoleChanged,
  });
  final TextEditingController controller;
  final String roleFilter;
  final ValueChanged<String> onRoleChanged;

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
            hintText: 'Search name, email or ID...',
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
            for (final r in [
              ('all', Icons.groups_outlined),
              ('passenger', Icons.person_outline),
              ('driver', Icons.directions_car),
            ])
              ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(r.$2, size: 16),
                    Text(' ${r.$1.capitalize()}'),
                  ],
                ),
                selected: roleFilter == r.$1,
                onSelected: (_) => onRoleChanged(r.$1),
                selectedColor: const Color(0xFF6A27F7).withValues(alpha: .18),
                labelStyle: TextStyle(
                  color:
                      roleFilter == r.$1
                          ? const Color(0xFF4B18C9)
                          : Colors.black87,
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

extension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
