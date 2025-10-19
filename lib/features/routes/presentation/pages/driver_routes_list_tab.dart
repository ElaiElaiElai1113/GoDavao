import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:godavao/features/routes/presentation/pages/driver_route_edit_page.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/core/osrm_service.dart';
import 'package:godavao/core/reverse_geocoder.dart';

class DriverRoutesListTab extends StatefulWidget {
  const DriverRoutesListTab({super.key});

  @override
  State<DriverRoutesListTab> createState() => _DriverRoutesListTabState();
}

class _DriverRoutesListTabState extends State<DriverRoutesListTab> {
  final sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  bool _working = false;

  List<Map<String, dynamic>> _routes = [];
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  final Map<String, String> _addr = {};

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final me = sb.auth.currentUser;
    if (me == null) {
      setState(() {
        _loading = false;
        _error = 'You are not signed in.';
      });
      return;
    }

    try {
      final rows = await sb
          .from('driver_routes')
          .select('''
            id, driver_id, name, notes, is_active, route_mode,
            start_lat, start_lng, end_lat, end_lng,
            capacity_total, capacity_available,
            vehicle_id,
            vehicles!driver_routes_vehicle_id_fkey (make, model, plate),
            created_at,
            updated_at
          ''')
          .eq('driver_id', me.id)
          .order('updated_at', ascending: false)
          .order('created_at', ascending: false);

      await _ingest(
        (rows as List).map((e) => Map<String, dynamic>.from(e)).toList(),
      );
    } catch (e) {
      setState(() => _error = 'Failed to load routes.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    _sub?.cancel();
    _sub = sb
        .from('driver_routes')
        .stream(primaryKey: ['id'])
        .eq('driver_id', sb.auth.currentUser!.id)
        .listen((rows) async {
          await _ingest(rows.map((e) => Map<String, dynamic>.from(e)).toList());
        });
  }

  DateTime _ts(Map<String, dynamic> r, String key) {
  final v = r[key];
  if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

  Future<void> _ingest(List<Map<String, dynamic>> rows) async {
  // cache-aware reverse geocode
  Future<String> geotext(double? lat, double? lng) async {
    if (lat == null || lng == null) return '—';
    final key = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
    if (_addr.containsKey(key)) return _addr[key]!;
    final t = await reverseGeocodeText(lat, lng);
    _addr[key] = t;
    return t;
  }

  // enrich with readable addresses
  final enriched = await Future.wait(
    rows.map((r) async {
      final sLat = (r['start_lat'] as num?)?.toDouble();
      final sLng = (r['start_lng'] as num?)?.toDouble();
      final eLat = (r['end_lat'] as num?)?.toDouble();
      final eLng = (r['end_lng'] as num?)?.toDouble();
      return {
        ...r,
        'start_address': await geotext(sLat, sLng),
        'end_address': await geotext(eLat, eLng),
      };
    }),
  );

  // ⬇️ NEW: always keep newest edits on top (stream snapshots are unordered)
  enriched.sort((b, a) {
    final au = _ts(a, 'updated_at');
    final bu = _ts(b, 'updated_at');
    if (au != bu) return au.compareTo(bu); // DESC by updated_at
    final ac = _ts(a, 'created_at');
    final bc = _ts(b, 'created_at');
    return ac.compareTo(bc);              // DESC tie-breaker
  });

  if (!mounted) return;
  setState(() => _routes = enriched);
}

  Future<void> _toggleActive(String id, bool newVal) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await sb.from('driver_routes').update({'is_active': newVal}).eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newVal ? 'Route activated' : 'Route deactivated'),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _card(Map<String, dynamic> r) {
    final id = r['id'].toString();
    final start =
        (r['start_lat'] != null && r['start_lng'] != null)
            ? LatLng(
              (r['start_lat'] as num).toDouble(),
              (r['start_lng'] as num).toDouble(),
            )
            : null;
    final end =
        (r['end_lat'] != null && r['end_lng'] != null)
            ? LatLng(
              (r['end_lat'] as num).toDouble(),
              (r['end_lng'] as num).toDouble(),
            )
            : null;

    final isActive = (r['is_active'] as bool?) ?? true;
    final vehicle = (r['vehicles'] as Map?) ?? {};
    final vehicleText = [
      if (vehicle['make'] != null) vehicle['make'],
      if (vehicle['model'] != null) vehicle['model'],
      if (vehicle['plate'] != null) '(${vehicle['plate']})',
    ].whereType<String>().join(' ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (start != null && end != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 120,
                  child: FutureBuilder<Polyline>(
                    future: fetchOsrmRoute(start: start, end: end),
                    builder: (_, snap) {
                      final lines = <Polyline>[
                        if (snap.hasData)
                          snap.data!
                        else
                          Polyline(
                            points: [start, end],
                            strokeWidth: 3,
                            color: _purple,
                          ),
                      ];
                      return FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(
                            (start.latitude + end.latitude) / 2,
                            (start.longitude + end.longitude) / 2,
                          ),
                          initialZoom: 12.5,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                            subdomains: const ['a', 'b', 'c'],
                            userAgentPackageName: 'com.godavao.app',
                          ),
                          PolylineLayer(polylines: lines),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: start,
                                width: 26,
                                height: 26,
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.green,
                                ),
                              ),
                              Marker(
                                point: end,
                                width: 26,
                                height: 26,
                                child: const Icon(
                                  Icons.flag,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    (r['name'] as String?)?.trim().isNotEmpty == true
                        ? r['name']
                        : 'Route ${id.substring(0, 8)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: (isActive ? Colors.green : Colors.red).withOpacity(
                      0.1,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isActive ? 'ACTIVE' : 'INACTIVE',
                    style: TextStyle(
                      color: isActive ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${r['start_address']} → ${r['end_address']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(
                  'Seats ${r['capacity_available'] ?? '-'} / ${r['capacity_total'] ?? '-'}',
                  Icons.event_seat,
                ),
                if (vehicleText.isNotEmpty)
                  _chip(vehicleText, Icons.directions_car),
                _chip(
                  (r['route_mode'] ?? 'osrm').toString().toUpperCase(),
                  Icons.alt_route,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _primary(
                    label: isActive ? 'Deactivate' : 'Activate',
                    icon: Icons.power_settings_new,
                    onPressed: () => _toggleActive(id, !isActive),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _primary(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    onPressed: () async {
                      final updated = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DriverRouteEditPage(routeId: id),
                        ),
                      );
                      if (updated == true && mounted) {
                        _bootstrap();
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _purpleDark),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _primary({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(colors: [_purple, _purpleDark]),
          boxShadow: [
            BoxShadow(
              color: _purple.withOpacity(.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white, size: 18),
          label: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  /// 🔹 Reusable AppBar with translucent gradient (like confirm/passenger screens)
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_purple.withOpacity(0.4), Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),
      backgroundColor: const Color.fromARGB(3, 0, 0, 0),
      elevation: 1,
      scrolledUnderElevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: CircleAvatar(
          backgroundColor: Colors.white.withOpacity(0.9),
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: _purple,
              size: 18,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      title: const Text(
        'My Routes',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: _purpleDark,
          fontSize: 18,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: Center(child: Text(_error!)),
      );
    }

    if (_routes.isEmpty) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: RefreshIndicator(
          onRefresh: _bootstrap,
          child: ListView(
            children: const [
              SizedBox(height: 200),
              Center(
                child: Text(
                  'No routes yet. Create one in the next tab.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _bootstrap,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: _routes.map(_card).toList(),
        ),
      ),
    );
  }
}
