// lib/core/shared_fare_service.dart
import 'dart:math';

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/core/fare_service.dart';
import 'package:godavao/core/osrm_service.dart';

/// Service for calculating and managing distance-proportional fares
/// for shared rides with multiple passengers.
class SharedFareService {
  final SupabaseClient _supabase;
  final FareService _fareService;

  SharedFareService({
    SupabaseClient? client,
    FareService? fareService,
  })  : _supabase = client ?? Supabase.instance.client,
        _fareService = fareService ?? FareService();

  /// Calculate distance-proportional fares for all passengers on a driver route.
  ///
  /// This method:
  /// 1. Fetches the driver's full route (start to end)
  /// 2. Fetches all matched passengers for this route
  /// 3. Calculates each passenger's distance along the route
  /// 4. Uses distance-proportional pricing to split the total route fare
  /// 5. Updates each passenger's fare in the database
  ///
  /// Returns [SharedFareBreakdown] with complete fare distribution details.
  Future<SharedFareBreakdown> calculateAndStoreSharedFares(
    String driverRouteId, {
    DateTime? when,
    double? platformFeeRate,
    double surgeMultiplier = 1.0,
  }) async {
    // 1. Fetch driver route details
    final routeData = await _fetchDriverRoute(driverRouteId);
    final routeStart = LatLng(
      routeData['start_lat'] as double,
      routeData['start_lng'] as double,
    );
    final routeEnd = LatLng(
      routeData['end_lat'] as double,
      routeData['end_lng'] as double,
    );

    // 2. Fetch all matched passengers for this route
    final passengers = await _fetchMatchedPassengers(driverRouteId);

    if (passengers.isEmpty) {
      throw Exception('No passengers found for route $driverRouteId');
    }

    // 3. Calculate distance for each passenger along the route
    final passengerDistances = await _calculatePassengerDistances(
      routeStart,
      routeEnd,
      passengers,
    );

    // 4. Create SharedPassenger objects
    final sharedPassengers = passengerDistances.map((p) {
      return SharedPassenger(
        id: p['ride_request_id'] as String,
        distanceKm: p['distance_km'] as double,
      );
    }).toList();

    // 5. Calculate distance-proportional fares
    final fareBreakdown = await _fareService.estimateSharedDistanceFare(
      routeStart: routeStart,
      routeEnd: routeEnd,
      passengers: sharedPassengers,
      when: when,
      platformFeeRate: platformFeeRate,
      surgeMultiplier: surgeMultiplier,
    );

    // 6. Update each passenger's fare in the database
    await _updatePassengerFares(fareBreakdown.passengerFares);

    return fareBreakdown;
  }

  /// Fetch driver route details from database
  Future<Map<String, dynamic>> _fetchDriverRoute(String routeId) async {
    try {
      final result = await _supabase
          .from('driver_routes')
          .select('id, start_lat, start_lng, end_lat, end_lng')
          .eq('id', routeId)
          .single();

      return result as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to fetch driver route: $e');
    }
  }

  /// Fetch all matched passengers for a driver route
  Future<List<Map<String, dynamic>>> _fetchMatchedPassengers(
    String routeId,
  ) async {
    try {
      final activeStatuses = ['pending', 'accepted', 'en_route'];

      final result = await _supabase
          .from('ride_matches')
          .select('''
            ride_request_id,
            status,
            ride_requests!inner(
              id,
              pickup_lat,
              pickup_lng,
              destination_lat,
              destination_lng
            )
          ''')
          .eq('driver_route_id', routeId)
          .inFilter('ride_matches.status', activeStatuses);

      return (result as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch matched passengers: $e');
    }
  }

  /// Calculate each passenger's distance along the route
  ///
  /// For each passenger, this calculates:
  /// - Distance from route start to passenger pickup
  /// - Distance from passenger pickup to passenger dropoff
  /// - Total = pickup_distance + trip_distance
  Future<List<Map<String, dynamic>>> _calculatePassengerDistances(
    LatLng routeStart,
    LatLng routeEnd,
    List<Map<String, dynamic>> passengers,
  ) async {
    final results = <Map<String, dynamic>>[];

    for (final passenger in passengers) {
      final requestData = passenger['ride_requests'] as Map<String, dynamic>;
      final pickup = LatLng(
        requestData['pickup_lat'] as double,
        requestData['pickup_lng'] as double,
      );
      final destination = LatLng(
        requestData['destination_lat'] as double,
        requestData['destination_lng'] as double,
      );

      // Calculate distance from route start to passenger pickup
      final pickupDistance = await _calculateRouteDistance(routeStart, pickup);

      // Calculate distance from passenger pickup to destination
      final tripDistance = await _calculateRouteDistance(pickup, destination);

      // Total distance this passenger travels along the route
      final totalDistance = pickupDistance + tripDistance;

      results.add({
        'ride_request_id': requestData['id'] as String,
        'pickup_distance_km': pickupDistance,
        'trip_distance_km': tripDistance,
        'distance_km': totalDistance,
      });
    }

    return results;
  }

  /// Calculate route distance between two points
  Future<double> _calculateRouteDistance(LatLng from, LatLng to) async {
    try {
      final routeData = await fetchOsrmRouteDetailed(start: from, end: to);
      return routeData.distanceMeters / 1000.0;
    } catch (_) {
      // Fallback to Haversine distance
      const double earthRadiusKm = 6371.0;
      final dLat = _toRad(to.latitude - from.latitude);
      final dLon = _toRad(to.longitude - from.longitude);
      final lat1 = _toRad(from.latitude);
      final lat2 = _toRad(to.latitude);

      final a = (sin(dLat / 2) * sin(dLat / 2)) +
          (sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2));
      final c = 2 * atan2(sqrt(a), sqrt(1 - a));

      return earthRadiusKm * c;
    }
  }

  double _toRad(double degrees) => degrees * pi / 180.0;

  /// Update each passenger's fare in the database
  Future<void> _updatePassengerFares(List<PassengerFare> passengerFares) async {
    for (final fare in passengerFares) {
      try {
        await _supabase
            .from('ride_requests')
            .update({
              'fare': fare.total,
              'distance_km': fare.distanceKm,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', fare.passengerId);
      } catch (e) {
        // Log error but continue updating other passengers
        print('Failed to update fare for ${fare.passengerId}: $e');
      }
    }
  }

  /// Get shared fare breakdown for a route (recalculate without storing)
  Future<SharedFareBreakdown> getSharedFareBreakdown(
    String driverRouteId, {
    DateTime? when,
    double? platformFeeRate,
    double surgeMultiplier = 1.0,
  }) async {
    final routeData = await _fetchDriverRoute(driverRouteId);
    final routeStart = LatLng(
      routeData['start_lat'] as double,
      routeData['start_lng'] as double,
    );
    final routeEnd = LatLng(
      routeData['end_lat'] as double,
      routeData['end_lng'] as double,
    );

    final passengers = await _fetchMatchedPassengers(driverRouteId);
    final passengerDistances = await _calculatePassengerDistances(
      routeStart,
      routeEnd,
      passengers,
    );

    final sharedPassengers = passengerDistances.map((p) {
      return SharedPassenger(
        id: p['ride_request_id'] as String,
        distanceKm: p['distance_km'] as double,
      );
    }).toList();

    return await _fareService.estimateSharedDistanceFare(
      routeStart: routeStart,
      routeEnd: routeEnd,
      passengers: sharedPassengers,
      when: when,
      platformFeeRate: platformFeeRate,
      surgeMultiplier: surgeMultiplier,
    );
  }
}
