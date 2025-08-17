import 'package:supabase_flutter/supabase_flutter.dart';

class SafetyService {
  final SupabaseClient supabase;
  SafetyService(this.supabase);

  Future<List<Map<String, dynamic>>> listContacts() async {
    final uid = supabase.auth.currentUser!.id;
    final rows = await supabase
        .from('trusted_contacts')
        .select('*')
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return (rows as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> addContact({
    required String name,
    String? phone,
    String? email,
    bool sms = true,
    bool emailNotify = false,
  }) async {
    final uid = supabase.auth.currentUser!.id;
    await supabase.from('trusted_contacts').insert({
      'user_id': uid,
      'name': name,
      'phone': phone,
      'email': email,
      'notify_by_sms': sms,
      'notify_by_email': emailNotify,
    });
  }

  Future<void> deleteContact(String id) async {
    await supabase.from('trusted_contacts').delete().eq('id', id);
  }

  Future<void> logSOS({
    required String rideId,
    required double lat,
    required double lng,
    String? message,
  }) async {
    final uid = supabase.auth.currentUser!.id;
    await supabase.from('sos_alerts').insert({
      'ride_id': rideId,
      'user_id': uid,
      'lat': lat,
      'lng': lng,
      'message': message,
    });
  }
}
