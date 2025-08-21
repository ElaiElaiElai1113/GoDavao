import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VehicleSwitcher extends StatefulWidget {
  const VehicleSwitcher({
    super.key,
    this.onChanged,
    this.chipPadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.wrapSpacing = 8,
    this.runSpacing = 8,
  });

  /// Called with the selected vehicle row after switching default.
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

  static const _purple = Color(0xFF6A27F7);

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

      final res = await _sb
          .from('vehicles')
          .select('id, make, model, plate, seats, is_default')
          .eq('driver_id', uid)
          .order('is_default', ascending: false);

      _vehicles = (res as List).cast<Map<String, dynamic>>();
      _selectedId =
          _vehicles.firstWhere(
                (v) => v['is_default'] == true,
                orElse: () => _vehicles.isNotEmpty ? _vehicles.first : {},
              )['id']
              as String?;
    } on PostgrestException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setDefault(String vehicleId) async {
    if (_selectedId == vehicleId) return;

    final prev = _selectedId;
    setState(() => _selectedId = vehicleId); // optimistic

    try {
      final uid = _sb.auth.currentUser!.id;

      // Set selected as default…
      await _sb
          .from('vehicles')
          .update({'is_default': true})
          .eq('id', vehicleId)
          .eq('driver_id', uid);

      // …and unset others explicitly (safety)
      await _sb
          .from('vehicles')
          .update({'is_default': false})
          .eq('driver_id', uid)
          .neq('id', vehicleId);

      // Notify parent
      final selected = _vehicles.firstWhere((v) => v['id'] == vehicleId);
      widget.onChanged?.call(selected);

      // Refresh list to reflect DB state
      await _loadVehicles();
    } catch (e) {
      if (mounted) setState(() => _selectedId = prev);
      if (!mounted) return;
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
      return const Text('No vehicles found');
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

            String label = [
              if (make.isNotEmpty) make,
              if (model.isNotEmpty) model,
              if (plate.isNotEmpty) '($plate)',
              if (seats > 0) '· $seats',
            ].join(' ');
            if (label.isEmpty) label = 'Vehicle ${id.substring(0, 6)}';

            return ChoiceChip(
              label: Padding(
                padding: widget.chipPadding,
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : null,
                  ),
                ),
              ),
              selected: selected,
              selectedColor: _purple,
              onSelected: (_) => _setDefault(id),
              shape: StadiumBorder(
                side: BorderSide(color: selected ? _purple : Colors.black12),
              ),
              backgroundColor: Colors.grey.shade100,
            );
          }).toList(),
    );
  }
}
