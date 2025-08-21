import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart'
    as gpa;

import 'package:godavao/core/osrm_service.dart';
import 'package:godavao/main.dart' show localNotify;

// NOTE: keep the import path you’re using for the switcher.
// If your switcher lives somewhere else, update this path accordingly.
import 'package:godavao/features/routes/presentation/pages/vehicle_switcher.dart';
import 'package:godavao/features/auth/presentation/vehicle_form.dart';

class DriverRoutePage extends StatefulWidget {
  const DriverRoutePage({super.key});
  @override
  State<DriverRoutePage> createState() => _DriverRoutePageState();
}

class _DriverRoutePageState extends State<DriverRoutePage> {
  final MapController _mapController = MapController();
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Map/routing
  LatLng? _start;
  LatLng? _end;
  Polyline? _route;

  // Vehicle selection (fed by VehicleSwitcher)
  String? _vehicleId;
  int? _vehicleSeats;

  // UI state
  bool _publishing = false;
  bool _checkingVehicles = true;
  bool _hasAnyVehicle = false;
  String? _error;

  // Styles
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _checkHasVehicles();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  InputDecoration _decor({String? label, String? hint}) =>
      const InputDecoration(border: UnderlineInputBorder()).copyWith(
        labelText: label,
        hintText: hint,
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: _purple, width: 2),
        ),
      );

  Future<void> _checkHasVehicles() async {
    setState(() {
      _checkingVehicles = true;
      _error = null;
    });
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        _hasAnyVehicle = false;
      } else {
        final res = await _sb
            .from('vehicles')
            .select('id')
            .eq('driver_id', uid)
            .limit(1);
        _hasAnyVehicle = (res as List).isNotEmpty;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _checkingVehicles = false);
    }
  }

  /// Long-press: 1) set start  2) set end (fetch OSRM)  3) reset with new start
  void _onMapLongPress(TapPosition _, LatLng latlng) async {
    if (_start == null) {
      setState(() {
        _start = latlng;
        _end = null;
        _route = null;
        _error = null;
      });
      return;
    }
    if (_end == null) {
      setState(() => _end = latlng);
      try {
        final fetched = await fetchOsrmRoute(start: _start!, end: _end!);
        setState(() => _route = fetched);
      } catch (e) {
        setState(() => _error = 'Routing failed: $e');
      }
      return;
    }
    // third press resets start
    setState(() {
      _start = latlng;
      _end = null;
      _route = null;
      _error = null;
    });
  }

  Future<void> _publishRoute() async {
    if (_vehicleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a vehicle first.')),
      );
      return;
    }
    if (_route == null || _start == null || _end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Long-press map to set start & end.')),
      );
      return;
    }

    setState(() => _publishing = true);
    try {
      final user = _sb.auth.currentUser;
      if (user == null) throw 'Not signed in';

      // encode polyline for storage
      final coords =
          _route!.points.map((p) => [p.latitude, p.longitude]).toList();
      final encoded = gpa.encodePolyline(coords);
      final seats = _vehicleSeats ?? 1;

      await _sb.from('driver_routes').insert({
        'driver_id': user.id,
        'vehicle_id': _vehicleId,
        'name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'route_polyline': encoded,
        'start_lat': _start!.latitude,
        'start_lng': _start!.longitude,
        'end_lat': _end!.latitude,
        'end_lng': _end!.longitude,
        'capacity_total': seats,
        'capacity_available': seats,
        'is_active': true, // optional: auto-activate on publish
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Route published!')));
      }

      await localNotify.show(
        0,
        'Route Published',
        'Your driver route has been published.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'routes_channel',
            'Route Alerts',
            channelDescription: 'Notifications for route publishing',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );

      // reset canvas for next route
      if (!mounted) return;
      setState(() {
        _nameCtrl.clear();
        _notesCtrl.clear();
        _start = null;
        _end = null;
        _route = null;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Publish failed: $e');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('Create Driver Route')),
      body: Stack(
        children: [
          // Map
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                center: _start ?? const LatLng(7.1907, 125.4553), // Davao
                zoom: 13,
                onLongPress: _onMapLongPress,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.yourcompany.godavao',
                ),
                if (_route != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _route!.points,
                        strokeWidth: 4,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                if (_start != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _start!,
                        width: 30,
                        height: 30,
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.green,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                if (_end != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _end!,
                        width: 30,
                        height: 30,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Optional error banner
          if (_error != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.red.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ),

          // Bottom summary card (matches your Figma style)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step hint
                    Row(
                      children: [
                        const Icon(
                          Icons.touch_app,
                          size: 18,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _start == null
                              ? 'Long-press to set START'
                              : _end == null
                              ? 'Long-press to set DESTINATION'
                              : 'Long-press again to reset START',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Vehicle area (switcher or add)
                    if (_checkingVehicles)
                      const SizedBox(
                        height: 36,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else if (!_hasAnyVehicle)
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'No vehicles yet. Add one to publish routes.',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Add Vehicle'),
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const VehicleForm(),
                                ),
                              );
                              await _checkHasVehicles();
                            },
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vehicle',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          // The switcher updates _vehicleId/_vehicleSeats via callback
                          VehicleSwitcher(
                            onChanged: (vehicle) {
                              setState(() {
                                _vehicleId = vehicle['id'] as String?;
                                _vehicleSeats = (vehicle['seats'] as int?) ?? 0;
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('Seats'),
                              const SizedBox(width: 8),
                              Chip(
                                label: Text(
                                  _vehicleSeats == null
                                      ? '—'
                                      : '${_vehicleSeats!} seats',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                    const SizedBox(height: 10),

                    // Optional route meta
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: _decor(
                        label: 'Route name (optional)',
                        hint: 'e.g., Morning Commute',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _notesCtrl,
                      decoration: _decor(
                        label: 'Notes (optional)',
                        hint: 'e.g., Picks near Roxas Ave',
                      ),
                      maxLines: 2,
                    ),

                    const SizedBox(height: 12),

                    // Publish CTA with purple gradient (Figma)
                    SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [_purple, _purpleDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _purple.withOpacity(0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          icon:
                              _publishing
                                  ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Icon(
                                    Icons.publish,
                                    color: Colors.white,
                                  ),
                          label: Text(
                            _publishing ? 'Publishing…' : 'Publish Route',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          onPressed: _publishing ? null : _publishRoute,
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
