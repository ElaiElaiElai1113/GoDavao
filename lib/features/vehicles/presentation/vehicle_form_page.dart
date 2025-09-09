import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/vehicle.dart';
import '../data/vehicle_service.dart';

class VehicleFormPage extends StatefulWidget {
  final Vehicle? vehicle;
  const VehicleFormPage({super.key, this.vehicle});

  @override
  State<VehicleFormPage> createState() => _VehicleFormPageState();
}

class _VehicleFormPageState extends State<VehicleFormPage> {
  final _svc = VehiclesService(Supabase.instance.client);
  final _form = GlobalKey<FormState>();

  late final TextEditingController plate;
  late final TextEditingController make;
  late final TextEditingController model;
  late final TextEditingController color;
  late final TextEditingController year;
  late final TextEditingController seats;

  bool _working = false;

  @override
  void initState() {
    super.initState();
    plate = TextEditingController(text: widget.vehicle?.plate ?? '');
    make = TextEditingController(text: widget.vehicle?.make ?? '');
    model = TextEditingController(text: widget.vehicle?.model ?? '');
    color = TextEditingController(text: widget.vehicle?.color ?? '');
    year = TextEditingController(text: widget.vehicle?.year?.toString() ?? '');
    seats = TextEditingController(
      text: widget.vehicle?.seats?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    plate.dispose();
    make.dispose();
    model.dispose();
    color.dispose();
    year.dispose();
    seats.dispose();
    super.dispose();
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _working = true);
    try {
      final y =
          year.text.trim().isNotEmpty ? int.tryParse(year.text.trim()) : null;
      final s =
          seats.text.trim().isNotEmpty ? int.tryParse(seats.text.trim()) : null;

      if (s == null || s < 1 || s > 10) {
        throw Exception('Seats must be between 1 and 10');
      }

      if (widget.vehicle == null) {
        await _svc.createVehicle(
          plate: plate.text.trim(),
          make: make.text.trim(),
          model: model.text.trim(),
          color: color.text.trim().isEmpty ? null : color.text.trim(),
          year: y,
          seats: s,
        );
      } else {
        final updated = Vehicle(
          id: widget.vehicle!.id,
          driverId: widget.vehicle!.driverId,
          plate: plate.text.trim(),
          make: make.text.trim(),
          model: model.text.trim(),
          color: color.text.trim().isEmpty ? null : color.text.trim(),
          year: y,
          seats: s,
          // keep whatever naming your Vehicle model expects
          isPrimary: widget.vehicle!.isPrimary,
          verificationStatus: widget.vehicle!.verificationStatus,
          verificationReason: widget.vehicle!.verificationReason,
        );
        await _svc.updateVehicle(
          widget.vehicle!.id,
          updated as Map<String, dynamic>,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.vehicle == null ? 'Vehicle added' : 'Vehicle updated',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.vehicle != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Vehicle' : 'Add Vehicle')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: plate,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Plate Number *',
                  border: OutlineInputBorder(),
                ),
                validator: _req,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: make,
                decoration: const InputDecoration(
                  labelText: 'Make *',
                  border: OutlineInputBorder(),
                ),
                validator: _req,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: model,
                decoration: const InputDecoration(
                  labelText: 'Model *',
                  border: OutlineInputBorder(),
                ),
                validator: _req,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: color,
                decoration: const InputDecoration(
                  labelText: 'Color (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: year,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Year',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: seats,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Seats *',
                        border: OutlineInputBorder(),
                      ),
                      validator: _req,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _working ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(
                  _working
                      ? 'Saving…'
                      : (isEdit ? 'Save Changes' : 'Add Vehicle'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
