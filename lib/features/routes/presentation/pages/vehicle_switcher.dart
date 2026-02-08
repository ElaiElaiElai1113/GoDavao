import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/common/empty_state.dart';
import 'package:godavao/common/app_colors.dart';

class VehicleSwitcher extends StatefulWidget {
  const VehicleSwitcher({
    super.key,
    this.onChanged,
    this.chipPadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.wrapSpacing = 8,
    this.runSpacing = 8,
  });

  /// Called with the selected (APPROVED) vehicle row after switching default or initial load.
  final void Function(Map<String, dynamic> vehicle)? onChanged;

  final EdgeInsets chipPadding;
  final double wrapSpacing;
  final double runSpacing;

  @override
  State<VehicleSwitcher> createState() => _VehicleSwitcherState();
}

class _VehicleSwitcherState extends State<VehicleSwitcher> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _vehicles = [];
  String? _selectedId;

  static const _purple = AppColors.purple;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _error = 'Not signed in';
          _vehicles = [];
          _selectedId = null;
          _loading = false;
        });
        return;
      }

      // Pull verification status so we can gate selection
      final res = await _sb
          .from('vehicles')
          .select('''
            id, make, model, plate, seats,
            is_default,
            verification_status,
            review_notes,
            orcr_key,
            created_at, submitted_at, reviewed_at
          ''')
          .eq('driver_id', uid)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);

      _vehicles =
          (res as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

      // Determine initial selection:
      // 1) default vehicle if APPROVED
      // 2) else first APPROVED
      // 3) else none (no approved vehicles yet)
      String? initial;
      final def = _vehicles.firstWhere(
        (v) =>
            v['is_default'] == true && v['verification_status'] == 'approved',
        orElse: () => {},
      );
      if (def.isNotEmpty) {
        initial = def['id'] as String?;
      } else {
        final firstApproved = _vehicles.firstWhere(
          (v) => v['verification_status'] == 'approved',
          orElse: () => {},
        );
        if (firstApproved.isNotEmpty) {
          initial = firstApproved['id'] as String?;
        }
      }

      _selectedId = initial;
      if (mounted) setState(() => _loading = false);

      // Inform parent if we have an approved selection
      if (_selectedId != null) {
        final selected = _vehicles.firstWhere((v) => v['id'] == _selectedId);
        widget.onChanged?.call(selected);
      }
    } on PostgrestException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setDefault(String vehicleId) async {
    if (_selectedId == vehicleId) return;

    // Check status locally first to give instant feedback
    final row = _vehicles.firstWhere((v) => v['id'] == vehicleId);
    final status = (row['verification_status'] as String?) ?? 'pending';
    if (status != 'approved') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'pending'
                ? 'This vehicle is still pending verification.'
                : 'This vehicle was rejected. Please re-submit OR/CR.',
          ),
        ),
      );
      return;
    }

    final prev = _selectedId;
    setState(() => _selectedId = vehicleId); // optimistic

    try {
      final uid = _sb.auth.currentUser!.id;

      // Make the selected one default…
      await _sb
          .from('vehicles')
          .update({'is_default': true})
          .eq('driver_id', uid)
          .eq('id', vehicleId);

      // …and unset others
      await _sb
          .from('vehicles')
          .update({'is_default': false})
          .eq('driver_id', uid)
          .neq('id', vehicleId);

      // Notify parent immediately
      widget.onChanged?.call(row);

      // Refresh to reflect DB state (optional)
      await _loadVehicles();
    } on PostgrestException catch (e) {
      // Database trigger may still block selection if not approved
      final friendly =
          e.message.contains('not approved')
              ? 'This vehicle isn’t approved yet. Please wait for verification or select another vehicle.'
              : e.message;
      setState(() => _selectedId = prev);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendly)));
    } catch (e) {
      setState(() => _selectedId = prev);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to switch vehicle: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 36,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_error != null) {
      return Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Colors.red),
          const SizedBox(width: 6),
          Expanded(
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVehicles,
            tooltip: 'Retry',
          ),
        ],
      );
    }

    if (_vehicles.isEmpty) {
      return const EmptyStateCard(
        icon: Icons.directions_car_outlined,
        title: 'No vehicles found',
        subtitle: 'Add a vehicle to continue.',
      );
    }

    return Wrap(
      spacing: widget.wrapSpacing,
      runSpacing: widget.runSpacing,
      children:
          _vehicles.map((v) {
            final id = v['id'] as String;
            final selected = id == _selectedId;
            final make = (v['make'] ?? '').toString();
            final model = (v['model'] ?? '').toString();
            final plate = (v['plate'] ?? '').toString();
            final seats = (v['seats'] as int?) ?? 0;
            final status = (v['verification_status'] as String?) ?? 'pending';
            final notes = (v['review_notes'] as String?)?.trim();

            String label = [
              if (make.isNotEmpty) make,
              if (model.isNotEmpty) model,
              if (plate.isNotEmpty) '($plate)',
              if (seats > 0) '· $seats',
            ].join(' ');
            if (label.trim().isEmpty) label = 'Vehicle ${id.substring(0, 6)}';

            final isApproved = status == 'approved';
            final isPending = status == 'pending';

            final statusChip = _StatusChip(status: status);

            final chip = ChoiceChip(
              label: Padding(
                padding: widget.chipPadding,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isApproved) ...[
                      Icon(
                        isPending ? Icons.lock_clock : Icons.lock_outline,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    statusChip,
                  ],
                ),
              ),
              selected: selected,
              selectedColor: _purple,
              onSelected: isApproved ? (_) => _setDefault(id) : null,
              shape: StadiumBorder(
                side: BorderSide(color: selected ? _purple : Colors.black12),
              ),
              backgroundColor: Colors.grey.shade100,
              disabledColor: Colors.grey.shade200,
            );

            if (isApproved) return chip;

            // Add tooltip context for pending/rejected
            final tipText =
                isPending
                    ? 'Awaiting admin verification.'
                    : (notes?.isNotEmpty == true
                        ? 'Rejected: $notes'
                        : 'Rejected. Please re-submit documents.');
            return Tooltip(message: tipText, preferBelow: false, child: chip);
          }).toList(),
    );
  }
}

/* ---------------- UI bits ---------------- */

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    late final Color c;
    late final String text;

    switch (status) {
      case 'approved':
        c = Colors.green;
        text = 'Approved';
        break;
      case 'rejected':
        c = Colors.red;
        text = 'Rejected';
        break;
      default:
        c = Colors.orange;
        text = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: .2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

