import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SosService {
  final SupabaseClient _sb;
  SosService(this._sb);

  Future<Position> _getPosition() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw Exception('Location permission denied.');
    }
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> triggerSOS({String? rideId, bool notifyContacts = true}) async {
    final pos = await _getPosition();
    final insert = {
      'lat': pos.latitude,
      'lng': pos.longitude,
      if (rideId != null) 'ride_id': rideId,
    };

    final row = await _sb.from('sos_alerts').insert(insert).select().single();

    if (notifyContacts) {
      // Optional: call an Edge Function to notify contacts
      // await _sb.functions.invoke('send-sos', body: {'sos_id': row['id']});
    }
  }
}
