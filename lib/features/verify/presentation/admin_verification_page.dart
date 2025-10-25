// lib/features/verify/presentation/admin_verification_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/admin_service.dart';

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
            'id, name, role, verified_role, phone, verification_status, updated_at, verification_notes, verification_reviewed_at',
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

  Future<void> _openSubmission(Map<String, dynamic> row) async {
    final userId = row['id'].toString();

    // Small loader while fetching URLs
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    List<Map<String, dynamic>> docs = const [];
    try {
      // Requires: AdminVerificationService.fetchSubmissionDocsForUser
      docs = await admin.fetchSubmissionDocsForUser(userId);
    } catch (_) {
      // ignore or toast
    } finally {
      if (mounted) Navigator.pop(context);
    }

    if (!mounted) return;
    final isBusy = _busyIds.contains(userId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => _VerificationSubmissionSheet(
            userRow: row,
            docs: docs,
            busy: isBusy,
            onApprove: () => _approve(row),
            onReject: () => _reject(row),
          ),
    );
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
                onViewSubmission: _openSubmission, // NEW
                roleColor: _roleColor,
                format: _fmt,
                displayName: (r) => r['name'] ?? 'Unknown',
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
                displayName: (r) => r['name'] ?? 'Unknown',
                onViewSubmission: _openSubmission, // NEW
              ),
              _VerificationTab.static(
                loading: _loadingRejected,
                data: _filter(_rejected),
                label: 'Rejected',
                color: Colors.red.shade600,
                onRefresh: () => _loadHistory('rejected'),
                format: _fmt,
                roleColor: _roleColor,
                displayName: (r) => r['name'] ?? 'Unknown',
                onViewSubmission: _openSubmission, // NEW
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
    this.onViewSubmission,
  });

  final Stream<List<Map<String, dynamic>>>? stream;
  final List<Map<String, dynamic>>? data;
  final bool loading;
  final String label;
  final Color? color;
  final Future<void> Function()? onRefresh;
  final void Function(Map<String, dynamic>)? onApprove,
      onReject,
      onViewSubmission;
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
    void Function(Map<String, dynamic>)? onViewSubmission,
  }) => _VerificationTab(
    data: data,
    loading: loading,
    label: label,
    color: color,
    onRefresh: onRefresh,
    roleColor: roleColor,
    format: format,
    displayName: displayName,
    onViewSubmission: onViewSubmission,
  );

  @override
  Widget build(BuildContext context) {
    if (stream != null) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const _StateMessage(
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
        onViewSubmission:
            onViewSubmission != null ? () => onViewSubmission!(r) : null,
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
    this.onViewSubmission,
  });
  final Map<String, dynamic> row;
  final Color Function(String) roleColor;
  final String Function(dynamic) format;
  final String Function(Map<String, dynamic>) displayName;
  final Color? color;
  final bool busy;
  final VoidCallback? onApprove, onReject, onViewSubmission;

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
                          row['phone'],
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
                  _Tag(row['verification_status'] ?? '', color!),
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
            if (onViewSubmission != null ||
                onApprove != null ||
                onReject != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (onViewSubmission != null)
                      TextButton.icon(
                        onPressed: onViewSubmission,
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('View submission'),
                      ),
                    if (busy)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else ...[
                      if (onReject != null)
                        OutlinedButton.icon(
                          onPressed: onReject,
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                        ),
                      if (onApprove != null)
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

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(.12),
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
                selectedColor: const Color(0xFF6A27F7).withOpacity(.18),
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

/* ------------------ SUBMISSION SHEET + GALLERY (self-contained) ------------------ */

class _VerificationSubmissionSheet extends StatelessWidget {
  const _VerificationSubmissionSheet({
    required this.userRow,
    required this.docs,
    this.onApprove,
    this.onReject,
    this.busy = false,
  });

  final Map<String, dynamic> userRow;
  final List<Map<String, dynamic>> docs;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool busy;

  static const _purpleDark = Color(0xFF4B18C9);

  bool _isImage(Map d) {
    final mime = (d['mime'] ?? '').toString().toLowerCase();
    final url = (d['url'] ?? '').toString().toLowerCase();
    return mime.startsWith('image/') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.png') ||
        url.endsWith('.webp');
  }

  static String _prettyType(String t) {
    switch (t) {
      case 'id_front':
        return 'ID — Front';
      case 'id_back':
        return 'ID — Back';
      case 'selfie':
        return 'Selfie with ID';
      case 'license':
        return 'Driver’s License';
      case 'vehicle_orcr':
        return 'Vehicle OR/CR';
      default:
        return t.isEmpty ? 'Document' : t;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (userRow['name'] ?? 'Unknown').toString();
    final role = (userRow['role'] ?? '—').toString();
    final status = (userRow['verification_status'] ?? '').toString();

    final imageDocs = docs.where(_isImage).toList();
    final fileDocs = docs.where((d) => !_isImage(d)).toList();

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.6,
        maxChildSize: 0.96,
        builder:
            (_, ctrl) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Header w/ actions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: const Color(0xFFF2EEFF),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: _purpleDark,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Wrap(
                                spacing: 6,
                                children: [
                                  _chip(role.toUpperCase(), Colors.indigo),
                                  _chip(
                                    status.isEmpty ? 'pending' : status,
                                    status == 'approved'
                                        ? Colors.green
                                        : status == 'rejected'
                                        ? Colors.red
                                        : Colors.orange,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (onReject != null || onApprove != null)
                          Row(
                            children: [
                              if (onReject != null)
                                OutlinedButton.icon(
                                  onPressed: busy ? null : onReject,
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.red,
                                  ),
                                  label: const Text('Reject'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                ),
                              const SizedBox(width: 8),
                              if (onApprove != null)
                                FilledButton.icon(
                                  onPressed: busy ? null : onApprove,
                                  icon: const Icon(Icons.check_circle_outline),
                                  label:
                                      busy
                                          ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                          : const Text('Approve'),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  const Divider(height: 1),

                  Expanded(
                    child: ListView(
                      controller: ctrl,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      children: [
                        if (imageDocs.isNotEmpty) ...[
                          const Text(
                            'Photos',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _ImageGrid(
                            docs: imageDocs,
                            onOpenViewer: (index) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => _ImageGalleryPage(
                                        images: imageDocs,
                                        initialIndex: index,
                                      ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (fileDocs.isNotEmpty) ...[
                          const Text(
                            'Other Files',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Column(
                            children:
                                fileDocs.map((d) {
                                  final type = (d['type'] ?? '').toString();
                                  final url = (d['url'] ?? '').toString();
                                  final mime = (d['mime'] ?? '').toString();
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: ListTile(
                                      leading: const CircleAvatar(
                                        backgroundColor: Color(0xFFF2EEFF),
                                        child: Icon(
                                          Icons.insert_drive_file,
                                          color: _purpleDark,
                                        ),
                                      ),
                                      title: Text(_prettyType(type)),
                                      subtitle: Text(
                                        mime.isEmpty ? url : mime,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: const Text('Open'),
                                      onTap: () {
                                        showDialog(
                                          context: context,
                                          builder:
                                              (_) => AlertDialog(
                                                title: const Text('Open file'),
                                                content: SelectableText(url),
                                                actions: [
                                                  TextButton(
                                                    onPressed:
                                                        () => Navigator.pop(
                                                          context,
                                                        ),
                                                    child: const Text('Close'),
                                                  ),
                                                ],
                                              ),
                                        );
                                      },
                                    ),
                                  );
                                }).toList(),
                          ),
                        ],

                        if (imageDocs.isEmpty && fileDocs.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'No documents found for this submission.',
                              style: TextStyle(color: Color(0xFF667085)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  static Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(.12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.docs, required this.onOpenViewer});
  final List<Map<String, dynamic>> docs;
  final void Function(int) onOpenViewer;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: docs.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (_, i) {
        final d = docs[i];
        final url = (d['url'] ?? '').toString();
        final type = (d['type'] ?? '').toString();
        return GestureDetector(
          onTap: () => onOpenViewer(i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(url, fit: BoxFit.cover),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xCC000000),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                    ),
                    child: Text(
                      _VerificationSubmissionSheet._prettyType(type),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ImageGalleryPage extends StatefulWidget {
  const _ImageGalleryPage({
    required this.images,
    this.initialIndex = 0,
    super.key,
  });
  final List<Map<String, dynamic>> images;
  final int initialIndex;

  @override
  State<_ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<_ImageGalleryPage> {
  late final PageController _pc = PageController(
    initialPage: widget.initialIndex,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        title: const Text('Submission Photos'),
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.images.length,
        itemBuilder: (_, i) {
          final url = (widget.images[i]['url'] ?? '').toString();
          final type = (widget.images[i]['type'] ?? '').toString();
          return Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(child: Image.network(url, fit: BoxFit.contain)),
                  const SizedBox(height: 8),
                  Text(
                    _VerificationSubmissionSheet._prettyType(type),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
