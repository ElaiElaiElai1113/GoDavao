import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:godavao/common/app_colors.dart';
import 'package:godavao/common/error_state.dart';
import 'package:godavao/common/empty_state.dart';
import 'package:godavao/features/vehicles/data/vehicle_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({super.key});

  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  final _svc = VehiclesService(Supabase.instance.client);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  // Brand
  static const _purple = AppColors.purple;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = _svc.watchMine().listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _items = list;
          _loading = false;
          _error = null;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
      },
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _svc.listMine();
      setState(() => _items = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addVehicle() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddVehicleSheet(),
    );
    if (mounted) _load();
  }

  Future<void> _editVehicle(Map<String, dynamic> v) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditVehicleSheet(vehicle: v, svc: _svc),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_purple.withValues(alpha: 0.4), Colors.transparent],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        backgroundColor: const Color.fromARGB(3, 0, 0, 0),
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: CircleAvatar(
            backgroundColor: Colors.white.withValues(alpha: 0.9),
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: _purple,
                size: 18,
              ),
              onPressed: () => Navigator.maybePop(context),
              tooltip: 'Back',
            ),
          ),
        ),
        title: Text(
          'My Vehicles',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child:
            _loading
                ? const _ListSkeleton()
                : _error != null
                ? _ErrorBox(message: _error!, onRetry: _load)
                : _items.isEmpty
                ? _Empty(onAdd: _addVehicle)
                : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder:
                      (_, i) => _VehicleCard(
                        v: _items[i],
                        svc: _svc,
                        onChanged: _load,
                        onEdit: () => _editVehicle(_items[i]),
                      ),
                ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addVehicle,
        icon: const Icon(Icons.add),
        label: const Text('Add Vehicle'),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/* ---------------- Vehicle Card ---------------- */

class _VehicleCard extends StatefulWidget {
  final Map<String, dynamic> v;
  final VehiclesService svc;
  final VoidCallback onChanged;
  final VoidCallback onEdit;

  const _VehicleCard({
    required this.v,
    required this.svc,
    required this.onChanged,
    required this.onEdit,
  });

  @override
  State<_VehicleCard> createState() => _VehicleCardState();
}

class _VehicleCardState extends State<_VehicleCard> {
  bool _working = false;

  static const _purple = AppColors.purple;
  void _successSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(msg)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green.shade600,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<ImageSource?> _chooseSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Use camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _upload(bool isOR) async {
    final source = await _chooseSource();
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _working = true);
    try {
      final id = widget.v['id'] as String;
      if (isOR) {
        await widget.svc.uploadOR(vehicleId: id, file: File(picked.path));
        _toast('OR uploaded');
      } else {
        await widget.svc.uploadCR(vehicleId: id, file: File(picked.path));
        _toast('CR uploaded');
      }

      // 🔁 Re-do the verification flow automatically after a replacement
      try {
        await widget.svc.resubmitBoth(id);
        _toast('Documents updated — resubmitted for verification');
      } catch (_) {
        // If it wasn’t submitted before, fall back to first-time submit
        try {
          await widget.svc.submitForVerificationBoth(id);
          _toast('Documents updated — submitted for verification');
        } catch (e2) {
          _toast('Updated, but could not submit: $e2');
        }
      }

      widget.onChanged();
    } catch (e) {
      _toast('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _working = true);
    try {
      await widget.svc.submitForVerificationBoth(widget.v['id'] as String);
      _toast('Submitted for verification');
      widget.onChanged();
    } catch (e) {
      _toast('Submit failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _resubmit() async {
    setState(() => _working = true);
    try {
      await widget.svc.resubmitBoth(widget.v['id'] as String);
      _toast('Resubmitted for verification');
      widget.onChanged();
    } catch (e) {
      _toast('Resubmit failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _makeDefault() async {
    setState(() => _working = true);
    try {
      await widget.svc.setDefault(widget.v['id'] as String);
      if (!mounted) return;
      _successSnack('Default vehicle updated');
      widget.onChanged();
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _deleteVehicle() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Delete vehicle?'),
            content: const Text(
              'This will remove the vehicle and its documents. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirm != true) return;

    setState(() => _working = true);
    try {
      await widget.svc.deleteVehicle(widget.v['id'] as String);
      widget.onChanged();
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    final isDefault = (v['is_default'] as bool?) ?? false;
    final status = (v['verification_status'] ?? 'pending') as String;
    final notes = v['review_notes'] as String?;
    final orKey = v['or_key'] as String?;
    final crKey = v['cr_key'] as String?;

    final title = [
      v['year']?.toString(),
      v['make'],
      v['model'],
    ].where((e) => (e ?? '').toString().trim().isNotEmpty).join(' ');

    final subBits = <String>[
      if ((v['plate'] ?? '').toString().isNotEmpty) 'Plate: ${v['plate']}',
      if ((v['color'] ?? '').toString().isNotEmpty) 'Color: ${v['color']}',
      'Seats: ${v['seats'] ?? '—'}',
    ];
    final subtitle = subBits.join(' • ');

    final statusChip = _StatusChip(status: status);

    final hasOR = orKey != null && orKey.isNotEmpty;
    final hasCR = crKey != null && crKey.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _purple.withValues(alpha: .08),
                  child: Icon(
                    isDefault ? Icons.star : Icons.directions_car,
                    color: _purple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? 'Vehicle' : title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                        ),
                    ],
                  ),
                ),
                statusChip,
              ],
            ),
            if (_working) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 2),
            ],

            if (isDefault) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
                  const SizedBox(width: 6),
                  Text(
                    'Default vehicle',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.green),
                  ),
                ],
              ),
            ],

            if ((notes?.trim().isNotEmpty ?? false) &&
                status == 'rejected') ...[
              const SizedBox(height: 10),
              _NoteBanner(text: 'Review notes: $notes'),
            ],

            const SizedBox(height: 12),

            // Primary actions
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: isDefault ? Colors.grey.shade300 : _purple,
                    foregroundColor: isDefault ? Colors.black54 : Colors.white,
                  ),
                  icon: const Icon(Icons.star),
                  label: Text(isDefault ? 'Default' : 'Make Default'),
                  onPressed: _working || isDefault ? null : _makeDefault,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                  onPressed: _working ? null : widget.onEdit,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete),
                  label: const Text('Delete'),
                  onPressed: _working ? null : _deleteVehicle,
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ▼ Documents & verification — dropdown
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                title: Row(
                  children: [
                    const Icon(Icons.folder_open, size: 18, color: _purple),
                    const SizedBox(width: 8),
                    Text(
                      'Documents',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 5),
                    _DocChip(label: 'OR', hasIt: hasOR),
                    const SizedBox(width: 5),
                    _DocChip(label: 'CR', hasIt: hasCR),
                  ],
                ),
                subtitle: Text(
                  'Replacing a document restarts the review.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                expandedAlignment: Alignment.centerLeft,
                children: [
                  // Upload row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file),
                          label: Text(hasOR ? 'Replace OR' : 'Upload OR'),
                          onPressed: _working ? null : () => _upload(true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file),
                          label: Text(hasCR ? 'Replace CR' : 'Upload CR'),
                          onPressed: _working ? null : () => _upload(false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tip: use clear, well-lit photos for faster verification.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 10),

                  // Previews (kept compact with grid)
                  _DocPreviews(svc: widget.svc, orKey: orKey, crKey: crKey),
                  const SizedBox(height: 10),

                  // Submit block (submit/resubmit/pending/approved)
                  _SubmitBlock(
                    status: status,
                    hasOR: hasOR,
                    hasCR: hasCR,
                    working: _working,
                    onSubmit: _submit,
                    onResubmit: _resubmit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/* ---------------- Chips for OR/CR presence ---------------- */

class _DocChip extends StatelessWidget {
  final String label;
  final bool hasIt;
  const _DocChip({required this.label, required this.hasIt});
  @override
  Widget build(BuildContext context) {
    final bg = hasIt ? Colors.green.withValues(alpha: .12) : Colors.grey.shade200;
    final fg = hasIt ? Colors.green.shade700 : Colors.grey.shade700;
    final icon = hasIt ? Icons.check_circle : Icons.error_outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/* ---------------- Status Chip ---------------- */

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    late final (Color bg, Color fg, IconData icon, String label) v;
    switch (status) {
      case 'approved':
        v = (
          Colors.green.withValues(alpha: .12),
          Colors.green.shade700,
          Icons.verified,
          'Approved',
        );
        break;
      case 'rejected':
        v = (
          Colors.red.withValues(alpha: .12),
          Colors.red.shade700,
          Icons.error_outline,
          'Rejected',
        );
        break;
      case 'pending':
      default:
        v = (
          Colors.orange.withValues(alpha: .12),
          Colors.orange.shade700,
          Icons.hourglass_top,
          'Pending',
        );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: v.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(v.$3, size: 16, color: v.$2),
          const SizedBox(width: 6),
          Text(
            v.$4,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: v.$2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/* ---------------- Note Banner ---------------- */

class _NoteBanner extends StatelessWidget {
  final String text;
  const _NoteBanner({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: .2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

/* ---------------- Doc Previews (OR/CR) ---------------- */

class _DocPreviews extends StatelessWidget {
  final VehiclesService svc;
  final String? orKey;
  final String? crKey;
  const _DocPreviews({
    required this.svc,
    required this.orKey,
    required this.crKey,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _DocTile(
        title: 'OR',
        futureUrl: svc.signedUrl(orKey),
        empty: orKey == null || orKey!.isEmpty,
        heroTag: 'doc-or-${orKey ?? ""}',
      ),
      _DocTile(
        title: 'CR',
        futureUrl: svc.signedUrl(crKey),
        empty: crKey == null || crKey!.isEmpty,
        heroTag: 'doc-cr-${crKey ?? ""}',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preview',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            final isWide = c.maxWidth >= 520;
            return GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              crossAxisCount: isWide ? 2 : 1,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: isWide ? 16 / 9 : 3 / 2,
              children: tiles,
            );
          },
        ),
      ],
    );
  }
}

class _DocTile extends StatelessWidget {
  final String title;
  final Future<String?> futureUrl;
  final bool empty;
  final String? heroTag;

  const _DocTile({
    required this.title,
    required this.futureUrl,
    required this.empty,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    if (empty) {
      return _DocBox(
          child: Center(
            child: Text(
              'No $title uploaded',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ),
      );
    }

    return FutureBuilder<String?>(
      future: futureUrl,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _DocBox(
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return _DocBox(
            child: Center(
              child: Text(
                'No $title uploaded',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
            ),
          );
        }

        final tag = (heroTag ?? 'viewer-$title-$url');
        return _DocBox(
          child: InkWell(
            onTap: () => _openImageViewer(context, title, url, tag),
            child: Hero(
              tag: tag,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(url, fit: BoxFit.cover),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openImageViewer(
    BuildContext context,
    String title,
    String url,
    String heroTag,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder:
            (_, __, ___) => _FullScreenImageViewer(
              title: title,
              imageUrl: url,
              heroTag: heroTag,
            ),
        transitionsBuilder:
            (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }
}

class _FullScreenImageViewer extends StatefulWidget {
  final String title;
  final String imageUrl;
  final String heroTag;

  const _FullScreenImageViewer({
    required this.title,
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  // Optional: double-tap zoom
  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.98),
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title),
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        onDoubleTapDown: (d) => _doubleTapDetails = d,
        onDoubleTap: () {
          final pos = _doubleTapDetails?.localPosition;
          if (pos == null) return;

          const zoom = 2.5;
          final translation = Matrix4.translationValues(-pos.dx * (zoom - 1), -pos.dy * (zoom - 1), 0.0);
          final scaling = Matrix4.diagonal3Values(zoom, zoom, 1.0);
          final matrix = _controller.value.isIdentity()
              ? (scaling * translation) as Matrix4
              : Matrix4.identity();

          _controller.value = matrix;
        },
        child: Center(
          child: Hero(
            tag: widget.heroTag,
            child: InteractiveViewer(
              transformationController: _controller,
              panEnabled: true,
              minScale: 1.0,
              maxScale: 5.0,
              child: Image.network(
                widget.imageUrl,
                fit: BoxFit.contain,
                // Add gapless playback to avoid flicker on hero transition
                gaplessPlayback: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocBox extends StatelessWidget {
  final Widget child;
  const _DocBox({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

/* ---------------- Submit Block ---------------- */

class _SubmitBlock extends StatelessWidget {
  final String status;
  final bool hasOR;
  final bool hasCR;
  final bool working;
  final VoidCallback onSubmit;
  final VoidCallback onResubmit;

  const _SubmitBlock({
    required this.status,
    required this.hasOR,
    required this.hasCR,
    required this.working,
    required this.onSubmit,
    required this.onResubmit,
  });

  @override
  Widget build(BuildContext context) {
    final rejected = status == 'rejected';
    final approved = status == 'approved';
    final pending = status == 'pending';

    if (approved) {
      return Row(
        children: [
          const Icon(Icons.verified, size: 16, color: Colors.green),
          const SizedBox(width: 6),
          Text(
            'Approved',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.green,
            ),
          ),
        ],
      );
    }

    if (pending) {
      return Row(
        children: [
          const Icon(Icons.hourglass_top, size: 16, color: Colors.orange),
          const SizedBox(width: 6),
          Text(
            'Submitted — waiting for review',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.orange,
            ),
          ),
        ],
      );
    }

    // Rejected or never submitted
    final canSubmit = hasOR && hasCR && !working;
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: canSubmit ? (rejected ? onResubmit : onSubmit) : null,
        icon: Icon(rejected ? Icons.refresh : Icons.check_circle),
        label: Text(rejected ? 'Fix & Resubmit' : 'Submit for verification'),
      ),
    );
  }
}

/* ---------------- Empty State ---------------- */

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        EmptyStateCard(
          icon: Icons.directions_car_filled,
          title: 'No vehicles yet',
          subtitle: 'Add your vehicle and upload OR/CR to start accepting rides.',
          ctaLabel: 'Add a vehicle',
          onCta: onAdd,
        ),
      ],
    );
  }
}

/* ---------------- Error Box ---------------- */

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        ErrorStateCard(
          title: 'Failed to load vehicles',
          message: message,
          ctaLabel: 'Retry',
          onCta: onRetry,
        ),
      ],
    );
  }
}

/* ---------------- Skeleton Loader ---------------- */

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();
  @override
  Widget build(BuildContext context) {
    Widget box() => Container(
      height: 128,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemBuilder: (_, __) => box(),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: 4,
    );
  }
}

/* ---------------- Edit Vehicle Sheet ---------------- */

class _EditVehicleSheet extends StatefulWidget {
  final Map<String, dynamic> vehicle;
  final VehiclesService svc;
  const _EditVehicleSheet({required this.vehicle, required this.svc});

  @override
  State<_EditVehicleSheet> createState() => _EditVehicleSheetState();
}

class _EditVehicleSheetState extends State<_EditVehicleSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _make;
  late final TextEditingController _model;
  late final TextEditingController _plate;
  late final TextEditingController _color;
  late final TextEditingController _year;
  late final TextEditingController _seats;
  late final TextEditingController _orNumber;
  late final TextEditingController _crNumber;

  bool _saving = false;

  static const _purple = AppColors.purple;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    _make = TextEditingController(text: (v['make'] ?? '').toString());
    _model = TextEditingController(text: (v['model'] ?? '').toString());
    _plate = TextEditingController(text: (v['plate'] ?? '').toString());
    _color = TextEditingController(text: (v['color'] ?? '').toString());
    _year = TextEditingController(text: (v['year'] ?? '').toString());
    _seats = TextEditingController(
      text: (v['seats'] ?? 4).toString(),
    );
    _orNumber = TextEditingController(text: (v['or_number'] ?? '').toString());
    _crNumber = TextEditingController(text: (v['cr_number'] ?? '').toString());
  }

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _plate.dispose();
    _color.dispose();
    _year.dispose();
    _seats.dispose();
    _orNumber.dispose();
    _crNumber.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.svc.updateVehicleFromValues(
        vehicleId: widget.vehicle['id'] as String,
        make: _make.text.trim(),
        model: _model.text.trim(),
        plate: _plate.text.trim().isEmpty ? null : _plate.text.trim(),
        color: _color.text.trim().isEmpty ? null : _color.text.trim(),
        year:
            _year.text.trim().isEmpty ? null : int.tryParse(_year.text.trim()),
        seats: int.parse(_seats.text.trim()),
        orNumber: _orNumber.text.trim().isEmpty ? null : _orNumber.text.trim(),
        crNumber: _crNumber.text.trim().isEmpty ? null : _crNumber.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    return SingleChildScrollView(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: insets.bottom + 12,
          ),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Edit Vehicle',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'Details',
                  children: [
                    TextFormField(
                      controller: _make,
                      decoration: const InputDecoration(labelText: 'Make *'),
                      textInputAction: TextInputAction.next,
                      validator:
                          (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                    ),
                    TextFormField(
                      controller: _model,
                      decoration: const InputDecoration(labelText: 'Model *'),
                      textInputAction: TextInputAction.next,
                      validator:
                          (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _year,
                            decoration: const InputDecoration(labelText: 'Year'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _seats,
                            decoration: const InputDecoration(
                              labelText: 'Seats *',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              final n = int.tryParse((v ?? '').trim());
                              if (n == null) return 'Enter a number';
                              if (n < 1 || n > 10) return 'Seats must be 1–10';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    TextFormField(
                      controller: _plate,
                      decoration: const InputDecoration(labelText: 'Plate'),
                    ),
                    TextFormField(
                      controller: _color,
                      decoration: const InputDecoration(labelText: 'Color'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _Section(
                  title: 'OR / CR',
                  children: [
                    TextFormField(
                      controller: _orNumber,
                      decoration: const InputDecoration(labelText: 'OR Number'),
                    ),
                    TextFormField(
                      controller: _crNumber,
                      decoration: const InputDecoration(labelText: 'CR Number'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text(_saving ? 'Saving…' : 'Save changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------------- Add Vehicle Sheet ---------------- */

class _AddVehicleSheet extends StatefulWidget {
  const _AddVehicleSheet();

  @override
  State<_AddVehicleSheet> createState() => _AddVehicleSheetState();
}

class _AddVehicleSheetState extends State<_AddVehicleSheet> {
  final _form = GlobalKey<FormState>();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _plate = TextEditingController();
  final _color = TextEditingController();
  final _year = TextEditingController();
  final _seats = TextEditingController(text: '4');
  final _orNumber = TextEditingController();
  final _crNumber = TextEditingController();

  final _picker = ImagePicker();
  File? _orFile;
  File? _crFile;

  bool _isDefault = false;
  bool _saving = false;

  static const _purple = AppColors.purple;

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _plate.dispose();
    _color.dispose();
    _year.dispose();
    _seats.dispose();
    _orNumber.dispose();
    _crNumber.dispose();
    super.dispose();
  }

  Future<void> _pickFile(bool isOR) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Use camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );
    if (source == null) return;
    final x = await _picker.pickImage(
      source: source,
      imageQuality: 85,
    );
    if (x == null) return;
    setState(() => isOR ? _orFile = File(x.path) : _crFile = File(x.path));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final svc = VehiclesService(Supabase.instance.client);

      // 1️⃣ Create the vehicle and capture id
      final newId = await svc.createVehicle(
        make: _make.text.trim(),
        model: _model.text.trim(),
        plate: _plate.text.trim().isEmpty ? null : _plate.text.trim(),
        color: _color.text.trim().isEmpty ? null : _color.text.trim(),
        year:
            _year.text.trim().isEmpty ? null : int.tryParse(_year.text.trim()),
        seats: int.parse(_seats.text.trim()),

        orNumber: _orNumber.text.trim().isEmpty ? null : _orNumber.text.trim(),
        crNumber: _crNumber.text.trim().isEmpty ? null : _crNumber.text.trim(),
      );

      // 2️⃣ Respect default toggle if requested
      if (_isDefault) {
        await svc.setDefault(newId);
      }

      // 3️⃣ Upload OR/CR if provided
      bool uploadedOR = false, uploadedCR = false;
      if (_orFile != null) {
        await svc.uploadOR(vehicleId: newId, file: _orFile!);
        uploadedOR = true;
      }
      if (_crFile != null) {
        await svc.uploadCR(vehicleId: newId, file: _crFile!);
        uploadedCR = true;
      }

      if (uploadedOR && uploadedCR) {
        try {
          await svc.submitForVerificationBoth(newId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Submitted for verification.')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Saved but could not submit: $e')),
            );
          }
        }
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    return SingleChildScrollView(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: insets.bottom + 12,
          ),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Add Vehicle',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),

                // Base info
                _Section(
                  title: 'Details',
                  children: [
                    TextFormField(
                      controller: _make,
                      decoration: const InputDecoration(
                        labelText: 'Make *',
                        hintText: 'e.g., Toyota',
                      ),
                      textInputAction: TextInputAction.next,
                      validator:
                          (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                    ),
                    TextFormField(
                      controller: _model,
                      decoration: const InputDecoration(
                        labelText: 'Model *',
                        hintText: 'e.g., Vios',
                      ),
                      textInputAction: TextInputAction.next,
                      validator:
                          (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _year,
                            decoration: const InputDecoration(
                              labelText: 'Year',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _seats,
                            decoration: const InputDecoration(
                              labelText: 'Seats *',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              final n = int.tryParse((v ?? '').trim());
                              if (n == null) return 'Enter a number';
                              if (n < 1 || n > 10) return 'Seats must be 1–10';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    TextFormField(
                      controller: _plate,
                      decoration: const InputDecoration(labelText: 'Plate'),
                    ),
                    TextFormField(
                      controller: _color,
                      decoration: const InputDecoration(labelText: 'Color'),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                _Section(
                  title: 'OR / CR',
                  children: [
                    TextFormField(
                      controller: _orNumber,
                      decoration: const InputDecoration(labelText: 'OR Number'),
                    ),
                    TextFormField(
                      controller: _crNumber,
                      decoration: const InputDecoration(labelText: 'CR Number'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.upload_file),
                            label: Text(
                              _orFile == null ? 'Upload OR' : 'Replace OR',
                            ),
                            onPressed: () => _pickFile(true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.upload_file),
                            label: Text(
                              _crFile == null ? 'Upload CR' : 'Replace CR',
                            ),
                            onPressed: () => _pickFile(false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tip: use clear, well-lit photos for faster verification.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                SwitchListTile(
                  value: _isDefault,
                  onChanged: (v) => setState(() => _isDefault = v),
                  title: const Text('Set as default'),
                  contentPadding: EdgeInsets.zero,
                  activeTrackColor: _purple,
                ),
                const SizedBox(height: 8),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          ..._withSpacing(children, 8),
        ],
      ),
    );
  }
}

/* ---------------- helpers ---------------- */

List<Widget> _withSpacing(List<Widget> list, double spacing) {
  final out = <Widget>[];
  for (var i = 0; i < list.length; i++) {
    out.add(list[i]);
    if (i != list.length - 1) out.add(SizedBox(height: spacing));
  }
  return out;
}
