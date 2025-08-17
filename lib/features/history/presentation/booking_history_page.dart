import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:godavao/features/ride_status/presentation/passenger_ride_status_page.dart';
import 'package:godavao/features/ride_status/presentation/driver_ride_status_page.dart';

class BookingHistoryPage extends StatefulWidget {
  const BookingHistoryPage({super.key});

  @override
  State<BookingHistoryPage> createState() => _BookingHistoryPageState();
}

class _BookingHistoryPageState extends State<BookingHistoryPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  String _role = 'passenger';

  final List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String> _fmtAddr(double lat, double lng) async {
    try {
      final pm = await placemarkFromCoordinates(lat, lng);
      final m = pm.first;
      final parts = <String?>[m.thoroughfare, m.subLocality, m.locality];
      return parts
          .where((e) => e != null && e!.isNotEmpty)
          .cast<String>()
          .join(', ');
    } catch (_) {
      return 'Unknown';
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
    });

    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in';
      });
      return;
    }

    try {
      // 1) get role
      final urow =
          await supabase
              .from('users')
              .select('role')
              .eq('id', user.id)
              .maybeSingle();
      _role = ((urow as Map?)?['role'] as String?) ?? 'passenger';

      if (_role == 'driver') {
        await _loadDriverHistory(user.id);
      } else {
        await _loadPassengerHistory(user.id);
      }

      // newest first
      _items.sort(
        (a, b) => DateTime.parse(
          b['created_at'] as String,
        ).compareTo(DateTime.parse(a['created_at'] as String)),
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPassengerHistory(String uid) async {
    // completed/declined/cancelled for this passenger
    final data = await supabase
        .from('ride_requests')
        .select('''
          id,
          pickup_lat, pickup_lng,
          destination_lat, destination_lng,
          fare,
          status,
          created_at
        ''')
        .eq('passenger_id', uid)
        .inFilter('status', ['completed', 'declined', 'cancelled'])
        .order('created_at', ascending: false);

    final list =
        (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    for (final r in list) {
      final pLat = (r['pickup_lat'] as num).toDouble();
      final pLng = (r['pickup_lng'] as num).toDouble();
      final dLat = (r['destination_lat'] as num).toDouble();
      final dLng = (r['destination_lng'] as num).toDouble();

      _items.add({
        'ride_id': r['id'],
        'created_at': r['created_at'],
        'status': r['status'],
        'fare': (r['fare'] as num?)?.toDouble(),
        'pickup': {
          'lat': pLat,
          'lng': pLng,
          'address': await _fmtAddr(pLat, pLng),
        },
        'destination': {
          'lat': dLat,
          'lng': dLng,
          'address': await _fmtAddr(dLat, dLng),
        },
        // We could fetch driver name by joining through ride_matches -> driver_routes -> users,
        // but it's optional here. Keep null for now or fill later if needed.
        'counterparty_name': null,
      });
    }
  }

  Future<void> _loadDriverHistory(String uid) async {
    // For driver: query ride_matches for routes owned by this driver,
    // and join the ride_requests + passenger user name.
    final data = await supabase
        .from('ride_matches')
        .select(r'''
          id,
          status,
          created_at,
          ride_request_id,
          driver_route_id,
          ride_requests (
            id,
            pickup_lat, pickup_lng,
            destination_lat, destination_lng,
            created_at,
            users ( name )
          )
        ''')
        .inFilter('status', ['completed', 'declined']) // history for driver
        .order('created_at', ascending: false);

    final raw =
        (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    // filter in-memory to matches that belong to this driver's routes
    // (safer than over-joining: RLS-friendly and robust to nesting variety)
    final myRouteIdsResp = await supabase
        .from('driver_routes')
        .select('id')
        .eq('driver_id', uid);
    final myRouteIds =
        (myRouteIdsResp as List).map((e) => (e as Map)['id'] as String).toSet();

    for (final m in raw) {
      if (!myRouteIds.contains(m['driver_route_id'])) continue;
      final req = (m['ride_requests'] as Map?) ?? {};
      final pLat = (req['pickup_lat'] as num).toDouble();
      final pLng = (req['pickup_lng'] as num).toDouble();
      final dLat = (req['destination_lat'] as num).toDouble();
      final dLng = (req['destination_lng'] as num).toDouble();

      final passengerName =
          (req['users'] is Map)
              ? (req['users'] as Map)['name'] as String?
              : (req['users'] is List && (req['users'] as List).isNotEmpty)
              ? ((req['users'] as List).first as Map)['name'] as String?
              : null;

      _items.add({
        'ride_id': req['id'] ?? m['ride_request_id'],
        'created_at': (req['created_at'] ?? m['created_at']) as String,
        'status': m['status'],
        'fare': null, // fare is on ride_requests; include if you store it
        'pickup': {
          'lat': pLat,
          'lng': pLng,
          'address': await _fmtAddr(pLat, pLng),
        },
        'destination': {
          'lat': dLat,
          'lng': dLng,
          'address': await _fmtAddr(dLat, dLng),
        },
        'counterparty_name': passengerName,
      });
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'completed':
        return Colors.green;
      case 'declined':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.black87;
    }
  }

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF6A27F7);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Booking History')),
        body: Center(child: Text('Error: $_error')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Booking History')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final it = _items[i];
            final dt = DateFormat(
              'MMM d, y • h:mm a',
            ).format(DateTime.parse(it['created_at'] as String));
            final status = it['status'] as String;
            final pickupAddr = (it['pickup'] as Map)['address'] as String;
            final destAddr = (it['destination'] as Map)['address'] as String;

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Route line
                    Text(
                      '$pickupAddr → $destAddr',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(dt, style: const TextStyle(color: Colors.black54)),

                    if (it['counterparty_name'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _role == 'driver'
                            ? 'Passenger: ${it['counterparty_name']}'
                            : 'Driver: ${it['counterparty_name']}',
                      ),
                    ],
                    if (it['fare'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Fare: ₱${(it['fare'] as double).toStringAsFixed(2)}',
                      ),
                    ],

                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor(status).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: _statusColor(status),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            final rideId = it['ride_id'] as String;
                            if (_role == 'driver') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) =>
                                          DriverRideStatusPage(rideId: rideId),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => PassengerRideStatusPage(
                                        rideId: rideId,
                                      ),
                                ),
                              );
                            }
                          },
                          style: TextButton.styleFrom(foregroundColor: purple),
                          child: const Text('View details'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
