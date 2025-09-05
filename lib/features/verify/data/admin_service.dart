import 'package:supabase_flutter/supabase_flutter.dart';

class AdminVerificationService {
  AdminVerificationService(this.client);
  final SupabaseClient client;

  /// Watch for pending requests
  Stream<List<Map<String, dynamic>>> watchPending() {
    return client
        .from('verification_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending');
  }

  /// Watch for approved requests
  Stream<List<Map<String, dynamic>>> watchApproved() {
    return client
        .from('verification_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'approved');
  }

  /// Watch for rejected requests
  Stream<List<Map<String, dynamic>>> watchRejected() {
    return client
        .from('verification_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'rejected');
  }

  /// Fetch requests (optionally by status)
  Future<List<Map<String, dynamic>>> fetch({String? status}) async {
    var q = client
        .from('verification_requests')
        .select('*, users:users(id, role, verification_status)');
    if (status != null) q = q.eq('status', status);
    return await q.order('created_at');
  }

  /// Approve a request
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

  /// Reject a request
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
