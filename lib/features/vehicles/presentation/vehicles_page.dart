import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/vehicle.dart';
import '../data/vehicle_service.dart';
import 'vehicle_card.dart';
import 'vehicle_form_page.dart';

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({super.key});

  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  final _svc = VehicleService(Supabase.instance.client);
  bool _loading = true;
  String? _error;
  List<Vehicle> _items = [];

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
      final items = await _svc.listMyVehicles();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load vehicles';
        _loading = false;
      });
    }
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Delete vehicle?'),
            content: const Text('This action cannot be undone.'),
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
    if (ok != true) return;
    await _svc.deleteVehicle(id);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Vehicle deleted')));
  }

  Future<void> _setPrimary(String id) async {
    await _svc.setPrimary(id);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Primary vehicle updated')));
  }

  void _openForm({Vehicle? v}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VehicleFormPage(vehicle: v)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Vehicles')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                onRefresh: _load,
                child:
                    _items.isEmpty
                        ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text('No vehicles yet. Tap + to add one.'),
                            ),
                          ],
                        )
                        : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final v = _items[i];
                            return VehicleCard(
                              v: v,
                              onEdit: () => _openForm(v: v),
                              onDelete: () => _delete(v.id),
                              onMakePrimary: () => _setPrimary(v.id),
                            );
                          },
                        ),
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Vehicle'),
      ),
    );
  }
}
