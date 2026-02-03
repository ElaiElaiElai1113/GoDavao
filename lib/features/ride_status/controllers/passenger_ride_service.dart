import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for handling passenger ride operations.
class PassengerRideService {
  final SupabaseClient _supabase;

  PassengerRideService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  /// Fetch ride composite data via RPC
  Future<Map<String, dynamic>> fetchRideComposite(String rideId) async {
    try {
      final result = await _supabase
          .rpc<Map<String, dynamic>>('passenger_ride_by_id', params: {'p_ride_id': rideId})
          .select()
          .single();

      return result.cast<String, dynamic>();
    } catch (e) {
      throw Exception('Failed to fetch ride composite: $e');
    }
  }

  /// Fetch passenger note and pricing extras from ride_requests
  Future<Map<String, dynamic>> fetchPassengerNoteAndPricingExtras(
    String rideId,
  ) async {
    try {
      final result = await _supabase
          .from('ride_requests')
          .select(
            'passenger_note, fare_basis, carpool_discount_pct, weather_desc, surge_multiplier, fare',
          )
          .eq('id', rideId)
          .maybeSingle();

      return (result as Map?)?.cast<String, dynamic>() ?? {};
    } catch (e) {
      throw Exception('Failed to fetch passenger note and pricing: $e');
    }
  }

  /// Fetch payment intent for a ride
  Future<Map<String, dynamic>?> fetchPayment(String rideId) async {
    try {
      final result = await _supabase
          .from('payment_intents')
          .select('ride_id, status, amount')
          .eq('ride_id', rideId)
          .maybeSingle();

      return (result as Map?)?.cast<String, dynamic>();
    } catch (e) {
      throw Exception('Failed to fetch payment: $e');
    }
  }

  /// Fetch match facts (match ID and seats allocated)
  Future<Map<String, dynamic>> fetchMatchFacts(String rideId) async {
    try {
      final result = await _supabase
          .from('ride_matches')
          .select('id, seats_allocated')
          .eq('ride_request_id', rideId)
          .maybeSingle();

      if (result == null) {
        return {'matchId': null, 'seatsBilled': 1};
      }

      final row = (result as Map).cast<String, dynamic>();
      final seats = ((row['seats_allocated'] as num?)?.toInt() ?? 1).clamp(1, 6);

      return {
        'matchId': row['id']?.toString(),
        'seatsBilled': seats,
      };
    } catch (e) {
      throw Exception('Failed to fetch match facts: $e');
    }
  }

  /// Fetch platform fee rate from app_settings
  Future<double?> fetchPlatformFeeRate() async {
    try {
      final result = await _supabase
          .from('app_settings')
          .select('key, value, value_num')
          .eq('key', 'platform_fee_rate')
          .maybeSingle();

      if (result == null) return null;

      final row = (result as Map).cast<String, dynamic>();
      final n = (row['value_num'] as num?) ?? (row['value'] as num?);
      final parsed = n?.toDouble() ?? double.tryParse(row['value']?.toString() ?? '');

      if (parsed != null && parsed >= 0 && parsed <= 1) {
        return parsed;
      }
      return null;
    } catch (e) {
      throw Exception('Failed to fetch platform fee rate: $e');
    }
  }

  /// Fetch carpool seat snapshot for a route
  Future<Map<String, int>> fetchCarpoolSeatSnapshot(String? routeId) async {
    if (routeId == null) {
      return {'activeBookings': 1, 'activeSeatsTotal': 1};
    }

    try {
      final rows = await _supabase
          .from('ride_matches')
          .select('ride_request_id, seats_allocated, ride_requests(status)')
          .eq('driver_route_id', routeId);

      final activeStatuses = {'pending', 'accepted', 'en_route'};
      final active = (rows as List)
          .cast<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((r) {
            final s = (r['ride_requests']?['status'] as String?)?.toLowerCase() ?? '';
            return activeStatuses.contains(s);
          })
          .toList();

      final bookings = active.map((r) => r['ride_request_id'].toString()).toSet().length;
      final seatsTotal = active.fold<int>(
        0,
        (acc, r) => acc + ((r['seats_allocated'] as num?)?.toInt() ?? 0),
      );

      return {
        'activeBookings': bookings == 0 ? 1 : bookings,
        'activeSeatsTotal': seatsTotal == 0 ? 1 : seatsTotal,
      };
    } catch (e) {
      throw Exception('Failed to fetch carpool seat snapshot: $e');
    }
  }

  /// Update ride request status
  Future<void> updateRideStatus(String rideId, String newStatus) async {
    try {
      await _supabase
          .from('ride_requests')
          .update({'status': newStatus})
          .eq('id', rideId);
    } catch (e) {
      throw Exception('Failed to update ride status: $e');
    }
  }

  /// Sync payment status for a ride request
  Future<void> syncPaymentForRide(
    String rideRequestId,
    String newStatus,
  ) async {
    try {
      final existingPayment = await _supabase
          .from('payment_intents')
          .select('id, status')
          .eq('ride_id', rideRequestId)
          .maybeSingle();

      if (existingPayment != null) {
        final paymentId = existingPayment['id']?.toString();
        if (paymentId != null) {
          await _supabase
              .from('payment_intents')
              .update({
                'status': newStatus,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', paymentId);
        }
      }
    } catch (e) {
      throw Exception('Failed to sync payment: $e');
    }
  }

  /// Cancel a ride request
  Future<void> cancelRideRequest(String rideId) async {
    try {
      await updateRideStatus(rideId, 'cancelled');
      await syncPaymentForRide(rideId, 'canceled');
    } catch (e) {
      throw Exception('Failed to cancel ride: $e');
    }
  }

  /// Create a stream subscription for ride_requests changes
  Stream<List<Map<String, dynamic>>> rideRequestStream(String rideId) {
    return _supabase
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('id', rideId);
  }

  /// Create a stream subscription for ride_matches changes
  Stream<List<Map<String, dynamic>>> rideMatchStream(String rideId) {
    return _supabase
        .from('ride_matches')
        .stream(primaryKey: ['id'])
        .eq('ride_request_id', rideId);
  }

  /// Subscribe to platform fee rate changes
  RealtimeChannel subscribeToPlatformFeeRate({
    required void Function(double) onRateUpdate,
  }) {
    final channel = _supabase.channel('app_settings:platform_fee_rate:view');

    void handler(PostgresChangeEvent event) {
      channel.onPostgresChanges(
        schema: 'public',
        table: 'app_settings',
        event: event,
        callback: (payload) {
          final rec = (payload.newRecord as Map?)?.cast<String, dynamic>();
          if (rec?['key']?.toString() != 'platform_fee_rate') return;

          final n = (rec?['value_num'] as num?) ?? (rec?['value'] as num?);
          final parsed = n?.toDouble() ?? double.tryParse(rec?['value']?.toString() ?? '');

          if (parsed != null && parsed >= 0 && parsed <= 1) {
            onRateUpdate(parsed);
          }
        },
      );
    }

    handler(PostgresChangeEvent.insert);
    handler(PostgresChangeEvent.update);

    return channel.subscribe();
  }

  /// Get driver info from ride data
  Map<String, dynamic>? extractDriverInfo(Map<String, dynamic>? ride) {
    if (ride == null) return null;

    final driver = ride['driver_routes'];
    if (driver == null) return null;

    final driverMap = driver is Map ? driver.cast<String, dynamic>() : null;
    if (driverMap == null) return null;

    final users = driverMap['users'];
    if (users == null) {
      return {
        'id': driverMap['driver_id']?.toString(),
        'name': 'Driver',
      };
    }

    final usersMap = users is Map ? users.cast<String, dynamic>() : null;
    if (usersMap == null) return null;

    return {
      'id': usersMap['id']?.toString(),
      'name': usersMap['name']?.toString() ?? 'Driver',
    };
  }

  /// Extract coordinates from ride data
  Map<String, LatLng?> extractCoordinates(Map<String, dynamic>? ride) {
    if (ride == null) {
      return {
        'pickup': null,
        'destination': null,
      };
    }

    final pickupLat = (ride['pickup_lat'] as num?)?.toDouble();
    final pickupLng = (ride['pickup_lng'] as num?)?.toDouble();
    final destLat = (ride['destination_lat'] as num?)?.toDouble();
    final destLng = (ride['destination_lng'] as num?)?.toDouble();

    return {
      'pickup': (pickupLat != null && pickupLng != null)
          ? LatLng(pickupLat, pickupLng)
          : null,
      'destination': (destLat != null && destLng != null)
          ? LatLng(destLat, destLng)
          : null,
    };
  }
}
