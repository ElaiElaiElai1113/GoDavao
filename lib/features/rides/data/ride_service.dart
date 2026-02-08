import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class RideService {
  final SupabaseClient _sb;
  RideService({SupabaseClient? client})
    : _sb = client ?? Supabase.instance.client;

  // ---------- CREATE / FETCH ----------

  Future<Map<String, dynamic>> getDriverRoute(String driverRouteId) async {
    final data =
        await _sb
            .from('driver_routes')
            .select('id, driver_id, capacity_total, capacity_available')
            .eq('id', driverRouteId)
            .maybeSingle();

    if (data == null) {
      throw PostgrestException(message: 'Route not found');
    }
    return (data as Map).cast<String, dynamic>();
  }

  /// Create a ride request (customize fields to your schema).
  Future<String> createRideRequest({
    required String passengerId,
    required int seatsRequested,
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    String? pickupAddress,
    String? destinationAddress,
  }) async {
    final insert =
        await _sb
            .from('ride_requests')
            .insert({
              'passenger_id': passengerId,
              'seats_requested': seatsRequested,
              'pickup_lat': pickupLat,
              'pickup_lng': pickupLng,
              'destination_lat': destinationLat,
              'destination_lng': destinationLng,
              if (pickupAddress != null) 'pickup_address': pickupAddress,
              if (destinationAddress != null)
                'destination_address': destinationAddress,
              'status': 'pending',
              'created_at': DateTime.now().toIso8601String(),
            })
            .select('id')
            .single();

    return insert['id'] as String;
  }

  /// Atomic seat allocation via RPC. Assumes your SQL function RETURNS ride_matches.
  Future<Map<String, dynamic>> allocateSeats({
    required String driverRouteId,
    required String rideRequestId,
    required int seatsRequested,
  }) async {
    return await _sb.rpc<Map<String, dynamic>>(
      'allocate_seats',
      params: {
        'p_driver_route_id': driverRouteId,
        'p_ride_request_id': rideRequestId,
        'p_seats_requested': seatsRequested,
      },
    );
  }

  // ---------- PASSENGER STATUS VIEW ----------

  /// Returns the active match (if any) for a given ride_request_id
  Future<Map<String, dynamic>?> getActiveMatchForRequest(
    String rideRequestId,
  ) async {
    final data =
        await _sb
            .from('ride_matches')
            .select(r'''
          id, status, seats_allocated, driver_route_id, created_at,
          ride_requests(passenger_id, status),
          driver_routes(id, driver_id, capacity_total, capacity_available)
        ''')
            .eq('ride_request_id', rideRequestId)
            .inFilter('status', ['pending', 'accepted', 'en_route'])
            .maybeSingle();

    return data == null ? null : (data as Map).cast<String, dynamic>();
  }

  // ---------- DRIVER PAGES ----------

  /// Driver's routes with basic info
  Future<List<Map<String, dynamic>>> getDriverRoutes(String driverId) async {
    final data = await _sb
        .from('driver_routes')
        .select('id, capacity_total, capacity_available, created_at')
        .eq('driver_id', driverId)
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// Matches per route (pending/active)
  Future<List<Map<String, dynamic>>> getMatchesForRoute(String routeId) async {
    final data = await _sb
        .from('ride_matches')
        .select(r'''
          id, status, seats_allocated, ride_request_id, created_at,
          ride_requests(
            id, passenger_id, seats_requested, status,
            pickup_address, destination_address,
            pickup_lat, pickup_lng, destination_lat, destination_lng
          )
        ''')
        .eq('driver_route_id', routeId)
        .inFilter('status', ['pending', 'accepted', 'en_route'])
        .order('created_at');

    return (data as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// Update a ride match status
  Future<void> updateMatchStatus(String matchId, String newStatus) async {
    await _sb
        .from('ride_matches')
        .update({'status': newStatus})
        .eq('id', matchId);
  }

  // ---------- REALTIME ----------
  // NOTE: We intentionally omit the `filter:` param (SDKs differ on its type).
  // We subscribe to table changes and filter inside the callback by IDs.

  /// Subscribe to a specific route row changes (capacity updates etc.)
  RealtimeChannel watchDriverRoute(
    String routeId,
    void Function(Map<String, dynamic> newRow) onChange,
  ) {
    final channel =
        _sb
            .channel('driver_route_$routeId')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'driver_routes',
              callback: (payload) {
                final newRec = payload.newRecord;
                final rec = (newRec as Map).cast<String, dynamic>();
                if (rec['id'] == routeId) {
                  onChange(rec);
                }
              },
            )
            .subscribe();
    return channel;
  }

  /// Subscribe to matches for a route (add/update/delete)
  RealtimeChannel watchMatchesForRoute(
    String routeId,
    void Function() onAnyChange,
  ) {
    final channel =
        _sb.channel('ride_matches_route_$routeId')
          ..onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'ride_matches',
            callback: (payload) {
              final rec = payload.newRecord;
              if ((rec as Map)['driver_route_id'] == routeId) {
                onAnyChange();
              }
            },
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'ride_matches',
            callback: (payload) {
              final rec = payload.newRecord;
              if ((rec as Map)['driver_route_id'] == routeId) {
                onAnyChange();
              }
            },
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'ride_matches',
            callback: (payload) {
              final oldRec = payload.oldRecord;
              if ((oldRec as Map)['driver_route_id'] == routeId) {
                onAnyChange();
              }
            },
          )
          ..subscribe();
    return channel;
  }
}
