import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/features/routes/presentation/pages/driver_route_geometry_page.dart';

class DriverRouteEditPage extends StatefulWidget {
  final String routeId;
  const DriverRouteEditPage({super.key, required this.routeId});

  @override
  State<DriverRouteEditPage> createState() => _DriverRouteEditPageState();
}

class _DriverRouteEditPageState extends State<DriverRouteEditPage> {
  final _sb = Supabase.instance.client;

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _notes = TextEditingController();
  final _capTotal = TextEditingController(text: '4');
  final _capAvail = TextEditingController(text: '4');

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  bool _isActive = true;
  String _routeMode = 'osrm'; // osrm | straight
  String? _vehicleId;

  List<Map<String, dynamic>> _vehicles = [];
  bool _hasActiveRide = false;

  static const _purple = Color(0xFF6A27F7);

  @override
  void initState() {
    super.initState();
    _load();
    for (final c in [_name, _notes, _capTotal, _capAvail]) {
      c.addListener(() => setState(() => _dirty = true));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _capTotal.dispose();
    _capAvail.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final me = _sb.auth.currentUser;
      if (me == null) throw Exception('Not signed in');

      final r =
          await _sb
              .from('driver_routes')
              .select('''
            id, name, notes, is_active, route_mode,
            capacity_total, capacity_available, vehicle_id
          ''')
              .eq('id', widget.routeId)
              .single();

      final vs = await _sb
          .from('vehicles')
          .select('id, make, model, plate')
          .eq('driver_id', me.id)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);

      _vehicles =
          (vs as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      _name.text = (r['name'] as String?) ?? '';
      _notes.text = (r['notes'] as String?) ?? '';
      _isActive = (r['is_active'] as bool?) ?? true;
      _routeMode = (r['route_mode'] as String?) ?? 'osrm';
      _vehicleId = r['vehicle_id']?.toString();

      final total = (r['capacity_total'] as num?)?.toInt() ?? 4;
      final avail = (r['capacity_available'] as num?)?.toInt() ?? total;
      _capTotal.text = total.toString();
      _capAvail.text = avail.toString();
      try {
  final matches = await _sb
      .from('ride_matches')
      .select('id')
      .eq('driver_route_id', widget.routeId)
      .inFilter('status', ['accepted', 'en_route']);
  _hasActiveRide = (matches as List).isNotEmpty;
} catch (_) {
  _hasActiveRide = false; // fail-open for UI; DB trigger still protects
}
      _dirty = false;
    } catch (e) {
      _error = 'Failed to load route: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _onWillPop() async {
    if (!_dirty || _saving) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('You have unsaved changes on this route.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
    );
    return leave == true;
  }

  // A small banner shown when this route has accepted/ongoing rides
Widget _blockedBanner() {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E1), // soft amber
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFECB3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Icon(Icons.lock_clock, color: Color(0xFFF57C00)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'This route has an accepted or ongoing ride. '
            'You can’t deactivate it until the ride is completed or cancelled.',
            style: TextStyle(color: Color(0xFF5D4037)),
          ),
        ),
      ],
    ),
  );
}

// Friendly bottom sheet to explain the block
void _showBlockedSheet() {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock, size: 36),
          const SizedBox(height: 10),
          const Text(
            'Route is in use',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            'You can’t deactivate this route because at least one passenger '
            'has already accepted the ride. Finish or cancel the active ride first.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ),
        ],
      ),
    ),
  );
}

// Turn Postgres errors into friendly copy
String _niceError(Object e) {
  if (e is PostgrestException) {
    final msg = (e.message ?? '').toString().toLowerCase();
    final details = (e.details ?? '').toString().toLowerCase();

    // Trigger error from our DB guard
    if (e.code == '45000' || msg.contains('cannot deactivate route')) {
      return 'You can’t deactivate this route while there’s an accepted or ongoing ride.';
    }

    // Capacity constraint from your table (chk_capacity_bounds)
    if (details.contains('chk_capacity_bounds') || msg.contains('chk_capacity_bounds')) {
      return 'You can’t deactivate this route while there’s an accepted or ongoing ride.';
    }

    // Other PG messages
    return e.message ?? 'Save failed.';
  }
  return 'Save failed. Please try again.';
}


  Future<void> _save() async {
  if (!_form.currentState!.validate()) return;

  setState(() => _saving = true);
  try {
    final total = int.parse(_capTotal.text.trim());
    final avail = int.parse(_capAvail.text.trim());
    final fixedAvail = avail.clamp(0, total);

    await _sb
        .from('driver_routes')
        .update({
          'name': _name.text.trim().isEmpty ? null : _name.text.trim(),
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          'is_active': _isActive,
          'route_mode': _routeMode,
          'vehicle_id': _vehicleId,
          'capacity_total': total,
          'capacity_available': fixedAvail,
        })
        .eq('id', widget.routeId)
        .select()
        .single(); // surface errors here

    if (!mounted) return;
    _dirty = false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Route updated')),
    );
    Navigator.pop(context, true);
  } on PostgrestException catch (e) {
    final msg = _niceError(e);

    // If DB blocked deactivation, show nicer UI + revert toggle
    if (e.code == '45000' ||
        (e.message ?? '').toLowerCase().contains('cannot deactivate route')) {
      if (!mounted) return;
      setState(() => _isActive = true);
      _showBlockedSheet(); // pretty explanation
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_niceError(e))),
    );
  } finally {
    if (mounted) setState(() => _saving = false);
  }
}

  Future<void> _openGeometryEditor() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DriverRouteGeometryPage(routeId: widget.routeId),
      ),
    );
    // If geometry was saved, reload the route (route_mode/anything else may have changed)
    if (updated == true && mounted) {
      await _load();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Geometry updated')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Edit Route';
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          backgroundColor: _purple,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Reload',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Edit geometry',
              onPressed: _loading ? null : _openGeometryEditor,
              icon: const Icon(Icons.place),
            ),
          ],
        ),
        body:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Form(
                    key: _form,
                    child: ListView(
                      children: [
                        _section('Basics', [
                          TextFormField(
                            controller: _name,
                            decoration: const InputDecoration(
                              labelText: 'Route name',
                              hintText: 'e.g., Morning run to Downtown',
                            ),
                          ),
                          TextFormField(
                            controller: _notes,
                            decoration: const InputDecoration(
                              labelText: 'Notes',
                            ),
                            maxLines: 3,
                          ),
                          // Wrap to allow onTap when switch is disabled
GestureDetector(
  onTap: (_hasActiveRide && _isActive) ? _showBlockedSheet : null,
  child: AbsorbPointer(
    absorbing: (_hasActiveRide && _isActive), // so the disabled switch won't toggle
    child: SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: const Text('Active'),
      subtitle: _hasActiveRide
          ? const Text(
              'This route has an accepted or ongoing ride. '
              'You can’t deactivate it until the ride is completed or cancelled.',
              style: TextStyle(fontSize: 12),
            )
          : null,
      value: _isActive,
      onChanged: (v) {
        setState(() {
          _isActive = v;
          _dirty = true;
        });
      },
    ),
  ),
),
                        ]),
                        const SizedBox(height: 10),
                        _section('Vehicle', [
                          DropdownButtonFormField<String?>(
                            value: _vehicleId,
                            decoration: const InputDecoration(
                              labelText: 'Select vehicle',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('— None —'),
                              ),
                              ..._vehicles.map((v) {
                                final id = v['id'].toString();
                                final label = [
                                  v['make'],
                                  v['model'],
                                  if ((v['plate'] ?? '').toString().isNotEmpty)
                                    '(${v['plate']})',
                                ].whereType<String>().join(' ');
                                return DropdownMenuItem<String?>(
                                  value: id,
                                  child: Text(label.isEmpty ? id : label),
                                );
                              }),
                            ],
                            onChanged:
                                (val) => setState(() {
                                  _vehicleId = val;
                                  _dirty = true;
                                }),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        _section('Capacity', [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _capTotal,
                                  decoration: const InputDecoration(
                                    labelText: 'Total seats',
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  validator: (v) {
                                    final n = int.tryParse((v ?? '').trim());
                                    if (n == null) return 'Enter a number';
                                    if (n < 1 || n > 10) return '1–10 only';
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: _capAvail,
                                  decoration: const InputDecoration(
                                    labelText: 'Available seats',
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  validator: (v) {
                                    final total =
                                        int.tryParse(_capTotal.text.trim()) ??
                                        1;
                                    final n = int.tryParse((v ?? '').trim());
                                    if (n == null) return 'Enter a number';
                                    if (n < 0) return 'Must be ≥ 0';
                                    if (n > total) return 'Cannot exceed total';
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ]),
                        const SizedBox(height: 10),
                        _section('Routing', [
                          DropdownButtonFormField<String>(
                            value: _routeMode,
                            decoration: const InputDecoration(
                              labelText: 'Route mode',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'osrm',
                                child: Text('OSRM (recommended)'),
                              ),
                              DropdownMenuItem(
                                value: 'straight',
                                child: Text('Straight line (fallback)'),
                              ),
                            ],
                            onChanged:
                                (v) => setState(() {
                                  _routeMode = v ?? 'osrm';
                                  _dirty = true;
                                }),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Mode changes affect how your route is drawn for passengers.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),

                        // ⬇️ New Geometry section
                        _section('Geometry', [
                          const Text(
                            'Edit the start & end points on a map.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 44,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.place),
                              label: const Text('Edit geometry on map'),
                              onPressed: _openGeometryEditor,
                            ),
                          ),
                        ]),

                        const SizedBox(height: 16),
                        SizedBox(
                          height: 48,
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

  Widget _section(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12.withOpacity(.08)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          ..._withSpacing(children, 10),
        ],
      ),
    );
  }
}

List<Widget> _withSpacing(List<Widget> list, double spacing) {
  final out = <Widget>[];
  for (var i = 0; i < list.length; i++) {
    out.add(list[i]);
    if (i != list.length - 1) out.add(SizedBox(height: spacing));
  }
  return out;
}
