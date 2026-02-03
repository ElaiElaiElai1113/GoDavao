import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:godavao/features/ride_status/models/match_card_model.dart';

/// Service for handling driver ride operations.
class DriverRideService {
  final SupabaseClient _supabase;

  DriverRideService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  /// Fetch all matches for a driver's routes
  Future<List<MatchCard>> fetchMatches(
    String driverId, {
    List<String>? routeIds,
  }) async {
    try {
      final query = _supabase
          .from('ride_matches')
          .select('''
            id,
            ride_request_id,
            driver_route_id,
            status,
            created_at,
            driver_routes!inner(
              id,
              route_name
            ),
            ride_requests!inner(
              id,
              passenger_id,
              seats_requested,
              status,
              pickup_address,
              dropoff_address,
              pickup_lat,
              pickup_lng,
              dropoff_lat,
              dropoff_lng
            )
          ''')
          .eq('driver_routes.driver_id', driverId)
          .inFilter('ride_matches.status', ['pending', 'accepted', 'en_route'])
          .order('created_at', ascending: true);

      final data = await query;

      return data.map<MatchCard>((row) {
        final matchRow = row as Map;
        final routeData = matchRow['driver_routes'] as Map? ?? {};
        final requestData = matchRow['ride_requests'] as Map? ?? {};

        return MatchCard(
          matchId: matchRow['id'] as String,
          rideRequestId: matchRow['ride_request_id'] as String,
          driverRouteId: matchRow['driver_route_id'] as String?,
          status: matchRow['status'] as String? ?? 'pending',
          createdAt: DateTime.parse(matchRow['created_at'] as String? ?? DateTime.now().toIso8601String()),
          passengerName: requestData['passenger_name'] as String? ?? 'Passenger',
          pickupAddress: requestData['pickup_address'] as String? ?? '',
          destinationAddress: requestData['dropoff_address'] as String? ?? '',
          fare: (matchRow['fare'] as num?)?.toDouble(),
          pax: requestData['seats_requested'] as int? ?? 1,
          driverRouteName: routeData['route_name'] as String?,
          passengerId: requestData['passenger_id'] as String?,
          pickupLat: (requestData['pickup_lat'] as num?)?.toDouble(),
          pickupLng: (requestData['pickup_lng'] as num?)?.toDouble(),
          destLat: (requestData['dropoff_lat'] as num?)?.toDouble(),
          destLng: (requestData['dropoff_lng'] as num?)?.toDouble(),
        );
      }).toList();
    } catch (e) {
      throw Exception('Failed to fetch matches: $e');
    }
  }

  /// Fetch declined and completed matches
  Future<List<MatchCard>> fetchHistoricalMatches(
    String driverId,
  ) async {
    try {
      final data = await _supabase
          .from('ride_matches')
          .select('''
            id,
            ride_request_id,
            driver_route_id,
            status,
            created_at,
            driver_routes!inner(
              id,
              route_name
            ),
            ride_requests!inner(
              id,
              passenger_id,
              seats_requested,
              status,
              pickup_address,
              dropoff_address,
              pickup_lat,
              pickup_lng,
              dropoff_lat,
              dropoff_lng
            )
          ''')
          .eq('driver_routes.driver_id', driverId)
          .inFilter('ride_matches.status', ['declined', 'completed', 'cancelled'])
          .order('created_at', ascending: true);

      return data.map<MatchCard>((row) {
        final matchRow = row as Map;
        final routeData = matchRow['driver_routes'] as Map? ?? {};
        final requestData = matchRow['ride_requests'] as Map? ?? {};

        return MatchCard(
          matchId: matchRow['id'] as String,
          rideRequestId: matchRow['ride_request_id'] as String,
          driverRouteId: matchRow['driver_route_id'] as String?,
          status: matchRow['status'] as String? ?? 'pending',
          createdAt: DateTime.parse(matchRow['created_at'] as String? ?? DateTime.now().toIso8601String()),
          passengerName: requestData['passenger_name'] as String? ?? 'Passenger',
          pickupAddress: requestData['pickup_address'] as String? ?? '',
          destinationAddress: requestData['dropoff_address'] as String? ?? '',
          fare: (matchRow['fare'] as num?)?.toDouble(),
          pax: requestData['seats_requested'] as int? ?? 1,
          driverRouteName: routeData['route_name'] as String?,
          passengerId: requestData['passenger_id'] as String?,
          pickupLat: (requestData['pickup_lat'] as num?)?.toDouble(),
          pickupLng: (requestData['pickup_lng'] as num?)?.toDouble(),
          destLat: (requestData['dropoff_lat'] as num?)?.toDouble(),
          destLng: (requestData['dropoff_lng'] as num?)?.toDouble(),
        );
      }).toList();
    } catch (e) {
      throw Exception('Failed to fetch historical matches: $e');
    }
  }

  /// Update match status
  Future<void> updateMatchStatus(
    String matchId,
    String newStatus, {
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      await _supabase
          .from('ride_matches')
          .update({
            'status': newStatus,
            ...?additionalData,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', matchId);
    } catch (e) {
      throw Exception('Failed to update match status: $e');
    }
  }

  /// Accept a ride match via RPC
  Future<Map<String, dynamic>> acceptMatch(
    String matchId,
    String rideRequestId,
  ) async {
    try {
      final result = await _supabase.rpc<Map<String, dynamic>>(
        'accept_ride_match',
        params: {
          'p_match_id': matchId,
          'p_ride_request_id': rideRequestId,
        },
      );

      return result;
    } catch (e) {
      throw Exception('Failed to accept match: $e');
    }
  }

  /// Decline a ride match
  Future<void> declineMatch(String matchId) async {
    try {
      await updateMatchStatus(matchId, 'declined');
    } catch (e) {
      throw Exception('Failed to decline match: $e');
    }
  }

  /// Start ride (en_route)
  Future<void> startRide(String matchId) async {
    try {
      await updateMatchStatus(matchId, 'en_route');
    } catch (e) {
      throw Exception('Failed to start ride: $e');
    }
  }

  /// Complete ride (dropped_off)
  Future<void> completeRide(String matchId) async {
    try {
      await updateMatchStatus(matchId, 'dropped_off');
    } catch (e) {
      throw Exception('Failed to complete ride: $e');
    }
  }

  /// Cancel ride
  Future<void> cancelRide(String matchId) async {
    try {
      await updateMatchStatus(matchId, 'cancelled');
    } catch (e) {
      throw Exception('Failed to cancel ride: $e');
    }
  }

  /// Get route capacities
  Future<Map<String, Map<String, int?>>> fetchRouteCapacities(
    List<String> routeIds,
  ) async {
    try {
      final data = await _supabase
          .from('driver_routes')
          .select('id, capacity_total, capacity_available')
          .inFilter('id', routeIds)
          .order('created_at', ascending: true);

      final result = <String, Map<String, int?>>{};

      for (final row in data) {
        final id = row['id'] as String;
        result[id] = {
          'total': row['capacity_total'] as int?,
          'available': row['capacity_available'] as int?,
        };
      }

      return result;
    } catch (e) {
      throw Exception('Failed to fetch route capacities: $e');
    }
  }

  /// Get passenger rating data
  Future<Map<String, Map<String, dynamic>>> fetchPassengerRatings(
    List<String> passengerIds,
  ) async {
    try {
      // Fetch ratings data
      final result = <String, Map<String, dynamic>>{};

      for (final passengerId in passengerIds) {
        // Try to get ratings for each passenger
        try {
          final ratingData = await _supabase
              .from('ratings')
              .select('ratee_user_id, avg(score), count(*)')
              .eq('ratee_user_id', passengerId)
              .single();

          result[passengerId] = {
            'avg': (ratingData['avg'] as num?)?.toDouble(),
            'count': (ratingData['count'] as num?)?.toInt() ?? 0,
          };
        } catch (_) {
          // If a passenger has no ratings yet
          result[passengerId] = {
            'avg': null,
            'count': 0,
          };
        }
      }

      return result;
    } catch (e) {
      throw Exception('Failed to fetch passenger ratings: $e');
    }
  }

  /// Sync payment status for a ride request
  Future<void> syncPaymentForRide(
    String rideRequestId,
    String newStatus,
  ) async {
    try {
      // Check if payment exists and update status
      final existingPayment = await _supabase
          .from('payment_intents')
          .select('id, status')
          .eq('ride_request_id', rideRequestId)
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

  /// Parse route data from database row
  Map<String, dynamic> parseRouteData(Map<String, dynamic> row) {
    return {
      'id': row['id'] as String?,
      'driver_id': row['driver_id'] as String?,
      'route_name': row['route_name'] as String?,
      'capacity_total': row['capacity_total'] as int?,
      'capacity_available': row['capacity_available'] as int?,
      'created_at': row['created_at'] as String?,
    };
  }
}
