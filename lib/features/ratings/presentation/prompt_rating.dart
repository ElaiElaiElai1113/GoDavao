import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/ratings_service.dart';
import './rate_user.dart';

/// Call this after you detect a ride is 'completed'.

Future<void> maybePromptForRating({
  required BuildContext context,
  required Map<String, dynamic> ride,
  required bool isDriverView,
}) async {
  final supabase = Supabase.instance.client;
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return;

  // Gather identities based on view
  final String rideId =
      (ride['id'] ?? ride['ride_request_id'] ?? ride['rideId']).toString();
  final String passengerId = ride['passenger_id'].toString();

  final String? driverId =
      (ride['driver_id'] ??
              ride['driver_routes']?['driver_id'] ??
              ride['driver']?['id'])
          ?.toString();

  if (driverId == null || rideId.isEmpty) return;

  final bool isRaterDriver = isDriverView;
  final String rateeUserId = isRaterDriver ? passengerId : driverId;
  final String rateeRole = isRaterDriver ? 'passenger' : 'driver';

  // Avoid prompting if user already rated
  final service = RatingsService(supabase);
  final existing = await service.getExistingRating(
    rideId: rideId,
    raterUserId: uid,
    rateeUserId: rateeUserId,
  );
  if (existing != null) return;

  // Optionally wait a tick for page settle
  await Future.delayed(const Duration(milliseconds: 200));

  // Fetch display name if you store it on users/profiles; fallback to "User"
  final rateeProfile = await supabase
      .from('users')
      .select('full_name, username')
      .eq('id', rateeUserId)
      .maybeSingle()
      .catchError((_) => null);

  final rateeName =
      (rateeProfile?['full_name'] ??
              rateeProfile?['username'] ??
              (isRaterDriver ? 'Passenger' : 'Driver'))
          as String;

  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder:
        (_) => RateUserSheet(
          rideId: rideId,
          raterUserId: uid,
          rateeUserId: rateeUserId,
          rateeName: rateeName,
          rateeRole: rateeRole,
        ),
  );
}
