// lib/features/rides/data/ride_repository.dart
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/core/fare_service.dart';

class RideRepository {
  final SupabaseClient supabase;
  final FareService fareService;

  RideRepository(this.supabase, {FareService? fareService})
    : fareService = fareService ?? FareService();

  /// Creates a ride request with an auto-computed fare.

  Future<String> createRideRequest({
    required String passengerId,
    required LatLng pickup,
    required LatLng destination,
    required String paymentMethod, // 'cash' or 'gcash'
  }) async {
    final fx = await fareService.estimate(
      pickup: pickup,
      destination: destination,
    );

    final insert = {
      'passenger_id': passengerId,
      'pickup_lat': pickup.latitude,
      'pickup_lng': pickup.longitude,
      'destination_lat': destination.latitude,
      'destination_lng': destination.longitude,
      'status': 'pending',
      'payment_method': paymentMethod, // ensure this column exists in DB
      'fare': fx.total, // final fare to charge
      // Optional audit columns (add to DB if you want them)
      // 'distance_km': fx.distanceKm,
      // 'duration_min': fx.durationMin,
    };

    final row =
        await supabase
            .from('ride_requests')
            .insert(insert)
            .select('id')
            .single();

    return (row['id'] as String);
  }
}
