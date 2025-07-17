import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ride_request_model.dart';

class RideRequestService {
  final supabase = Supabase.instance.client;

  Future<String> saveRideRequest(RideRequest ride) async {
    final response =
        await supabase
            .from('ride_requests')
            .insert({
              'passenger_id': ride.passengerId,
              'pickup_lat': ride.pickupLat,
              'pickup_lng': ride.pickupLng,
              'destination_lat': ride.destinationLat,
              'destination_lng': ride.destinationLng,
              'status': 'pending',
            })
            .select('id')
            .single();

    return response['id'] as String;
  }

  Future<void> matchWithDriver(
    int rideRequestId,
    LatLng pickup,
    LatLng destination,
  ) async {
    final driverRoutes = await supabase.from('driver_routes').select();

    for (final route in driverRoutes) {
      final startLat = route['start_lat'] as double;
      final startLng = route['start_lng'] as double;
      final endLat = route['end_lat'] as double;
      final endLng = route['end_lng'] as double;

      final isStartNearby =
          (pickup.latitude - startLat).abs() < 0.05 &&
          (pickup.longitude - startLng).abs() < 0.05;
      final isEndNearby =
          (destination.latitude - endLat).abs() < 0.05 &&
          (destination.longitude - endLng).abs() < 0.05;

      if (isStartNearby && isEndNearby) {
        await supabase.from('ride_matches').insert({
          'ride_request_id': rideRequestId,
          'driver_id': route['driver_id'],
        });
        break;
      }
    }
  }
}
