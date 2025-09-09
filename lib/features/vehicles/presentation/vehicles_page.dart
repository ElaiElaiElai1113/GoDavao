import 'package:flutter/material.dart';
import 'package:godavao/features/vehicles/data/vehicle_service.dart';
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
                        onMakeDefault: () async {
                          try {
                            await _svc.setDefault(_items[i]['id'] as String);
                            _load();
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed: $e')),
                            );
                          }
                        },
                        onDelete: () async {
                          try {
                            await _svc.deleteVehicle(_items[i]['id'] as String);
                            _load();
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed: $e')),
                            );
                          }
                        },
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

class _VehicleTile extends StatelessWidget {
  final Map<String, dynamic> v;
  final VoidCallback onMakeDefault;
  final VoidCallback onDelete;

  const _VehicleTile({
    required this.v,
    required this.onMakeDefault,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
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

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(isDefault ? Icons.star : Icons.directions_car),
        ),
        title: Text(title.isEmpty ? 'Vehicle' : title),
        subtitle: Text(subtitle),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'default') onMakeDefault();
            if (value == 'delete') onDelete();
          },
          itemBuilder:
              (_) => [
                const PopupMenuItem(
                  value: 'default',
                  child: Text('Make default'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
        ),
      ),
    );
  }
}

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
      await svc.addVehicle(
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
