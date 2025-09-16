// lib/features/ride_status/presentation/passenger_ride_status_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:godavao/features/chat/presentation/chat_page.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/ratings/presentation/user_rating.dart';
import 'package:godavao/features/payments/presentation/payment_status_chip.dart';

class PassengerRideStatusPage extends StatefulWidget {
  final String rideId;
  const PassengerRideStatusPage({super.key, required this.rideId});

  @override
  State<PassengerRideStatusPage> createState() =>
      _PassengerRideStatusPageState();
}

class _PassengerRideStatusPageState extends State<PassengerRideStatusPage> {
  final _sb = Supabase.instance.client;
  final _map = MapController();

  // Data
  Map<String, dynamic>? _ride;
  Map<String, dynamic>? _match;
  Map<String, dynamic>? _payment;

  bool _loading = true;
  String? _error;

  // Stream subs
  StreamSubscription<List<Map<String, dynamic>>>? _rideSub;
  StreamSubscription<List<Map<String, dynamic>>>? _matchSub;

  // Theme tokens
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _rideSub?.cancel();
    _matchSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Future.wait([_loadRide(), _loadMatch(), _loadPayment()]);
      _watchRide();
      _watchMatch();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRide() async {
    final res =
        await _sb
            .from('ride_requests')
            .select('''
          id, status, created_at, pickup_lat, pickup_lng,
          destination_lat, destination_lng, passenger_id, fare, seats,
          driver_route_id,
          users:passenger_id ( id, name )
        ''')
            .eq('id', widget.rideId)
            .single();
    if (!mounted) return;
    setState(() => _ride = (res as Map).cast<String, dynamic>());
  }

  Future<void> _loadMatch() async {
    final rows = await _sb
        .from('ride_matches')
        .select('''
          id, status, created_at,
          driver_id, driver_route_id, seats_allocated,
          drivers:driver_id ( id, name ),
          routes:driver_route_id ( id )
        ''')
        .eq('ride_request_id', widget.rideId)
        .order('created_at', ascending: true);
    if (!mounted) return;
    setState(() {
      _match =
          (rows is List && rows.isNotEmpty)
              ? (rows.last as Map).cast<String, dynamic>()
              : null;
    });
  }

  Future<void> _loadPayment() async {
    final res =
        await _sb
            .from('payment_intents')
            .select('ride_id, status, amount')
            .eq('ride_id', widget.rideId)
            .maybeSingle();
    if (!mounted) return;
    setState(() => _payment = (res as Map?)?.cast<String, dynamic>());
  }

  void _watchRide() {
    _rideSub?.cancel();
    _rideSub = _sb
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('id', widget.rideId)
        .listen((rows) async {
          if (!mounted) return;
          if (rows.isNotEmpty) {
            setState(() => _ride = Map<String, dynamic>.from(rows.first));
            await _loadPayment(); // keep payment in sync
          }
        });
  }

  void _watchMatch() {
    _matchSub?.cancel();
    _matchSub = _sb
        .from('ride_matches')
        .stream(primaryKey: ['id'])
        .eq('ride_request_id', widget.rideId)
        .order('created_at')
        .listen((rows) {
          if (!mounted) return;
          if (rows.isEmpty) {
            setState(() => _match = null);
            return;
          }
          setState(() => _match = Map<String, dynamic>.from(rows.last));
        });
  }

  // ====== Helpers ======
  String get _status {
    final s = (_ride?['status'] as String?) ?? 'pending';
    return s.toLowerCase();
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':
        return Colors.grey;
      case 'accepted':
        return Colors.blue;
      case 'en_route':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'canceled':
      case 'declined':
        return Colors.red;
      default:
        return Colors.black87;
    }
  }

  LatLng? get _pickup {
    final r = _ride;
    if (r == null) return null;
    final lat = r['pickup_lat'] as num?;
    final lng = r['pickup_lng'] as num?;
    if (lat == null || lng == null) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  LatLng? get _dropoff {
    final r = _ride;
    if (r == null) return null;
    final lat = r['destination_lat'] as num?;
    final lng = r['destination_lng'] as num?;
    if (lat == null || lng == null) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  // ====== Actions ======
  Future<void> _cancelRide() async {
    if (_ride == null) return;
    try {
      await _sb
          .from('ride_requests')
          .update({'status': 'canceled'})
          .eq('id', widget.rideId);
      await _sb
          .from('payment_intents')
          .update({'status': 'canceled'})
          .eq('ride_id', widget.rideId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ride canceled')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fare = (_ride?['fare'] as num?)?.toDouble();
    final passenger = (_ride?['users'] as Map?)?['name']?.toString() ?? 'You';
    final driverId = _match?['driver_id']?.toString();
    final driverName = (_match?['drivers'] as Map?)?['name']?.toString() ?? '—';

    final center =
        _pickup ?? _dropoff ?? const LatLng(7.1907, 125.4553); // Davao fallback

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Ride Status'),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        actions: [
          if (driverId != null) VerifiedBadge(userId: driverId, size: 22),
          if (driverId != null)
            IconButton(
              tooltip: 'Chat with driver',
              icon: const Icon(Icons.message_outlined),
              onPressed: () {
                final matchId = _match?['id']?.toString();
                if (matchId == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ChatPage(matchId: matchId)),
                );
              },
            ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text('Error: $_error'))
              : RefreshIndicator(
                onRefresh:
                    () async => await Future.wait([
                      _loadRide(),
                      _loadMatch(),
                      _loadPayment(),
                    ]),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 80),
                  children: [
                    // ===== Header chips =====
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Chip(
                            icon: Icons.info_outline,
                            label: _status.toUpperCase(),
                            color: _statusColor(_status).withOpacity(.12),
                            textColor: _statusColor(_status),
                          ),
                          if (fare != null)
                            _Chip(
                              icon: Icons.payments_outlined,
                              label: '₱${fare.toStringAsFixed(2)}',
                            ),
                          if (_payment != null)
                            PaymentStatusChip(
                              status: _payment!['status'] as String?,
                              amount: (_payment!['amount'] as num?)?.toDouble(),
                            ),
                        ],
                      ),
                    ),

                    // ===== Map preview =====
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: 220,
                          child: FlutterMap(
                            mapController: _map,
                            options: MapOptions(center: center, zoom: 13),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.godavao.app',
                              ),
                              MarkerLayer(
                                markers: [
                                  if (_pickup != null)
                                    Marker(
                                      point: _pickup!,
                                      width: 30,
                                      height: 30,
                                      child: const Icon(
                                        Icons.place,
                                        color: Colors.green,
                                        size: 28,
                                      ),
                                    ),
                                  if (_dropoff != null)
                                    Marker(
                                      point: _dropoff!,
                                      width: 30,
                                      height: 30,
                                      child: const Icon(
                                        Icons.flag,
                                        color: Colors.red,
                                        size: 26,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ===== Driver info =====
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.directions_car_outlined,
                            color: Colors.black54,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              driverId == null
                                  ? 'Waiting for driver'
                                  : 'Driver: $driverName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (driverId != null)
                            UserRatingBadge(userId: driverId, iconSize: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      bottomNavigationBar: _buildBottomBar(passenger, driverName, fare),
    );
  }

  Widget _buildBottomBar(String passenger, String driverName, double? fare) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.info_outline),
                label: const Text('Details'),
                onPressed:
                    () => _openDetailsSheet(
                      context: context,
                      passengerName: passenger,
                      driverName: driverName,
                      fare: fare,
                    ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PrimaryButton(
                label:
                    _status == 'pending' || _status == 'accepted'
                        ? 'Cancel ride'
                        : _status == 'en_route'
                        ? 'SOS'
                        : 'Close',
                icon:
                    _status == 'en_route'
                        ? Icons.emergency_share
                        : Icons.cancel_outlined,
                onPressed: () {
                  if (_status == 'en_route') {
                    _showSosDialog();
                  } else if (_status == 'pending' || _status == 'accepted') {
                    _cancelRide();
                  } else {
                    Navigator.maybePop(context);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetailsSheet({
    required BuildContext context,
    required String passengerName,
    required String driverName,
    double? fare,
  }) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Ride ID', widget.rideId),
              const SizedBox(height: 6),
              _detailRow('Status', _status.toUpperCase()),
              const Divider(height: 20),
              _detailRow('Passenger', passengerName),
              _detailRow('Driver', driverName),
              if (fare != null)
                _detailRow('Fare', '₱${fare.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              if (_payment != null)
                PaymentStatusChip(
                  status: _payment!['status'] as String?,
                  amount: (_payment!['amount'] as num?)?.toDouble(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void _showSosDialog() {
    showDialog<void>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Emergency'),
            content: const Text(
              'Do you want to trigger SOS and share your live location with your emergency contacts?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.emergency_share),
                label: const Text('Trigger SOS'),
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('SOS triggered')),
                  );
                },
              ),
            ],
          ),
    );
  }
}

/* -------------------- Small UI helpers -------------------- */

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final Color? textColor;
  const _Chip({
    required this.icon,
    required this.label,
    this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: textColor ?? Colors.black54),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [_purple, _purpleDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: _purple.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          icon: Icon(icon, color: Colors.white),
          label: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          onPressed: onPressed,
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
}
