import 'dart:io';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
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

  void _addVehicle() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddVehicleSheet(),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Vehicles')),
      body: RefreshIndicator(
        onRefresh: _load,
        child:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _ErrorBox(message: _error!, onRetry: _load)
                : _items.isEmpty
                ? _Empty(onAdd: _addVehicle)
                : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder:
                      (_, i) => _VehicleTile(
                        v: _items[i],
                        svc: _svc,
                        onChanged: _load,
                      ),
                ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addVehicle,
        icon: const Icon(Icons.add),
        label: const Text('Add vehicle'),
      ),
    );
  }
}

/* ---------------- Vehicle Tile ---------------- */

class _VehicleTile extends StatefulWidget {
  final Map<String, dynamic> v;
  final VehiclesService svc;
  final VoidCallback onChanged;

  const _VehicleTile({
    required this.v,
    required this.svc,
    required this.onChanged,
  });

  @override
  State<_VehicleTile> createState() => _VehicleTileState();
}

class _VehicleTileState extends State<_VehicleTile> {
  bool _working = false;

  Future<void> _uploadOR() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _working = true);
    try {
      await widget.svc.uploadOR(
        vehicleId: widget.v['id'] as String,
        file: File(picked.path),
      );
      _toast('OR uploaded');
      widget.onChanged();
    } catch (e) {
      _toast('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _uploadCR() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _working = true);
    try {
      await widget.svc.uploadCR(
        vehicleId: widget.v['id'] as String,
        file: File(picked.path),
      );
      _toast('CR uploaded');
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

  @override
  Widget build(BuildContext context) {
    final v = widget.v;

    final title = [
      v['year']?.toString(),
      v['make'],
      v['model'],
    ].where((e) => (e ?? '').toString().trim().isNotEmpty).join(' ');

    final subtitle = [
      if ((v['plate'] ?? '').toString().isNotEmpty) 'Plate: ${v['plate']}',
      if ((v['color'] ?? '').toString().isNotEmpty) 'Color: ${v['color']}',
      'Seats: ${v['seats'] ?? '—'}',
      'Status: ${(v['verification_status'] ?? 'pending')}'.toString(),
    ].join(' • ');

    final isDefault = (v['is_default'] as bool?) ?? false;
    final status = (v['verification_status'] ?? 'pending') as String;
    final notes = v['review_notes'] as String?;

    // separate keys (expect these columns exist in DB)
    final orKey = v['or_key'] as String?;
    final crKey = v['cr_key'] as String?;

    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Icon(isDefault ? Icons.star : Icons.directions_car),
        ),
        title: Text(title.isEmpty ? 'Vehicle' : title),
        subtitle: Text(subtitle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          // Default/Delete
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.star),
                label: const Text('Make Default'),
                onPressed:
                    _working
                        ? null
                        : () async {
                          try {
                            await widget.svc.setDefault(v['id'] as String);
                            widget.onChanged();
                          } catch (e) {
                            _toast('Failed: $e');
                          }
                        },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete),
                label: const Text('Delete'),
                onPressed:
                    _working
                        ? null
                        : () async {
                          try {
                            await widget.svc.deleteVehicle(v['id'] as String);
                            widget.onChanged();
                          } catch (e) {
                            _toast('Failed: $e');
                          }
                        },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Verification block
          _VerificationBlock(
            svc: widget.svc,
            vehicleId: v['id'] as String,
            status: status,
            notes: notes,
            working: _working,
            orKey: orKey,
            crKey: crKey,
            onUploadOR: _uploadOR,
            onUploadCR: _uploadCR,
            onSubmit: _submit,
            onResubmit: _resubmit,
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/* ---------------- Verification Block ---------------- */

class _VerificationBlock extends StatelessWidget {
  const _VerificationBlock({
    required this.svc,
    required this.vehicleId,
    required this.status,
    required this.notes,
    required this.working,
    required this.orKey,
    required this.crKey,
    required this.onUploadOR,
    required this.onUploadCR,
    required this.onSubmit,
    required this.onResubmit,
  });

  final VehiclesService svc;
  final String vehicleId;
  final String status;
  final String? notes;
  final bool working;

  final String? orKey;
  final String? crKey;

  final VoidCallback onUploadOR;
  final VoidCallback onUploadCR;
  final VoidCallback onSubmit;
  final VoidCallback onResubmit;

  bool get hasOR => (orKey != null && orKey!.isNotEmpty);
  bool get hasCR => (crKey != null && crKey!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final rejected = status == 'rejected';
    final approved = status == 'approved';
    final pending = status == 'pending';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rejected && (notes?.trim().isNotEmpty ?? false)) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Review notes: $notes',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Upload buttons
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: Text(hasOR ? 'Replace OR' : 'Upload OR'),
              onPressed: working ? null : onUploadOR,
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: Text(hasCR ? 'Replace CR' : 'Upload CR'),
              onPressed: working ? null : onUploadCR,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Preview OR
        FutureBuilder<String?>(
          future: svc.signedUrl(orKey),
          builder: (context, snap) {
            if (orKey == null || orKey!.isEmpty) {
              return const Text('No OR uploaded yet.');
            }
            if (!snap.hasData) {
              return const SizedBox(
                height: 32,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Loading OR preview…'),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Uploaded OR:'),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    snap.data!,
                    height: 160,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),

        // Preview CR
        FutureBuilder<String?>(
          future: svc.signedUrl(crKey),
          builder: (context, snap) {
            if (crKey == null || crKey!.isEmpty) {
              return const Text('No CR uploaded yet.');
            }
            if (!snap.hasData) {
              return const SizedBox(
                height: 32,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Loading CR preview…'),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Uploaded CR:'),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    snap.data!,
                    height: 160,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),

        if (!approved && hasOR && hasCR)
          FilledButton.icon(
            icon: Icon(rejected ? Icons.refresh : Icons.check_circle),
            label: Text(rejected ? 'Fix & Resubmit' : 'Submit'),
            onPressed: working ? null : (rejected ? onResubmit : onSubmit),
          ),

        if (pending) ...[
          const SizedBox(height: 8),
          Row(
            children: const [
              Icon(Icons.hourglass_top, size: 16, color: Colors.orange),
              SizedBox(width: 6),
              Text(
                'Submitted — waiting for review',
                style: TextStyle(color: Colors.orange),
              ),
            ],
          ),
        ],
        if (approved) ...[
          const SizedBox(height: 8),
          Row(
            children: const [
              Icon(Icons.verified, size: 16, color: Colors.green),
              SizedBox(width: 6),
              Text('Approved', style: TextStyle(color: Colors.green)),
            ],
          ),
        ],
      ],
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
      children: [
        const SizedBox(height: 60),
        const Icon(
          Icons.directions_car_filled,
          size: 64,
          color: Colors.black38,
        ),
        const SizedBox(height: 12),
        const Center(child: Text('No vehicles yet')),
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add a vehicle'),
          ),
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
        const SizedBox(height: 60),
        const Icon(Icons.error_outline, color: Colors.red, size: 48),
        const SizedBox(height: 12),
        SelectableText(
          'Failed to load vehicles:\n$message',
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
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
  bool _isDefault = false;
  bool _saving = false;

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _plate.dispose();
    _color.dispose();
    _year.dispose();
    _seats.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final svc = VehiclesService(Supabase.instance.client);
      await svc.createVehicle(
        make: _make.text.trim(),
        model: _model.text.trim(),
        plate: _plate.text.trim().isEmpty ? null : _plate.text.trim(),
        color: _color.text.trim().isEmpty ? null : _color.text.trim(),
        year:
            _year.text.trim().isEmpty ? null : int.tryParse(_year.text.trim()),
        seats: int.parse(_seats.text.trim()),
        isDefault: _isDefault,
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
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add Vehicle',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _make,
                decoration: const InputDecoration(labelText: 'Make *'),
                validator:
                    (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _model,
                decoration: const InputDecoration(labelText: 'Model *'),
                validator:
                    (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _plate,
                decoration: const InputDecoration(labelText: 'Plate'),
              ),
              TextFormField(
                controller: _color,
                decoration: const InputDecoration(labelText: 'Color'),
              ),
              TextFormField(
                controller: _year,
                decoration: const InputDecoration(labelText: 'Year'),
                keyboardType: TextInputType.number,
              ),
              TextFormField(
                controller: _seats,
                decoration: const InputDecoration(labelText: 'Seats *'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null) return 'Enter a number';
                  if (n < 1 || n > 10) return 'Seats must be 1–10';
                  return null;
                },
              ),
              SwitchListTile(
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
                title: const Text('Set as default'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
