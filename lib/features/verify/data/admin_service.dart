import 'package:supabase_flutter/supabase_flutter.dart';

class AdminVerificationService {
  AdminVerificationService(this.client);
  final SupabaseClient client;

  Stream<List<Map<String, dynamic>>> watchPending() {
    return client
        .from('verification_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending');
  }

  Future<List<Map<String, dynamic>>> fetch({String? status}) async {
    var q = client
        .from('verification_requests')
        .select('*, users:users(id, role, verification_status)');
    if (status != null) q = q.eq('status', status);
    return await q.order('created_at');
  }

  Future<void> approve(String id, {String? notes}) async {
    final uid = client.auth.currentUser!.id;
    await client
        .from('verification_requests')
        .update({
          'status': 'approved',
          'reviewed_by': uid,
          'reviewed_at': DateTime.now().toIso8601String(),
          if (notes != null) 'notes': notes,
        })
        .eq('id', id);
  }

  Future<void> reject(String id, {String? notes}) async {
    final uid = client.auth.currentUser!.id;
    await client
        .from('verification_requests')
        .update({
          'status': 'rejected',
          'reviewed_by': uid,
          'reviewed_at': DateTime.now().toIso8601String(),
          if (notes != null) 'notes': notes,
        })
        .eq('id', id);
  }
}
