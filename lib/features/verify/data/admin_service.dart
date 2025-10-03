import 'package:supabase_flutter/supabase_flutter.dart';

/// Enum values in your DB (public.verification_status)
class VerificationStatus {
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
}

class AdminVerificationService {
  AdminVerificationService(this.client);
  final SupabaseClient client;

  // -------------------- Streams --------------------

  Stream<List<Map<String, dynamic>>> watchPending() {
    return client
        .from('verification_requests')
        .stream(primaryKey: ['id']) // older SDK: no `columns` param
        .eq('status', VerificationStatus.pending);
  }

  Stream<List<Map<String, dynamic>>> watchApproved() {
    return client
        .from('verification_requests')
        .stream(primaryKey: ['id'])
        .eq('status', VerificationStatus.approved);
  }

  Stream<List<Map<String, dynamic>>> watchRejected() {
    return client
        .from('verification_requests')
        .stream(primaryKey: ['id'])
        .eq('status', VerificationStatus.rejected);
  }

  // -------------------- Queries --------------------

  /// Fetch requests (optionally filtered). Newest first.
  Future<List<Map<String, dynamic>>> fetch({String? status}) async {
    final List data =
        status == null
            ? await client
                .from('verification_requests')
                .select('*, users:users(id, role, verification_status)')
                .order('created_at')
            : await client
                .from('verification_requests')
                .select('*, users:users(id, role, verification_status)')
                .eq('status', status) // keep as text; server casts to enum
                .order('created_at');

    return data.cast<Map<String, dynamic>>();
  }

  /// Get one request by id (with joined user info).
  Future<Map<String, dynamic>?> getById(String requestId) async {
    final row =
        await client
            .from('verification_requests')
            .select('*, users:users(id, role, verification_status)')
            .eq('id', requestId)
            .maybeSingle();
    return row;
  }

  // -------------------- Actions (via RPC) --------------------

  Future<void> _process({
    required String requestId,
    required String actionEnum, // 'approved' | 'rejected'
    String? notes,
  }) async {
    final cleanedNotes = (notes?.trim().isEmpty ?? true) ? null : notes!.trim();

    await client.rpc(
      'process_verification_request',
      params: {
        'p_request_id': requestId,
        'p_action': actionEnum, // server maps to ENUM type
        'p_notes': cleanedNotes,
      },
    );
  }

  Future<void> approve(String id, {String? notes}) => _process(
    requestId: id,
    actionEnum: VerificationStatus.approved,
    notes: notes,
  );

  Future<void> reject(String id, {String? notes}) => _process(
    requestId: id,
    actionEnum: VerificationStatus.rejected,
    notes: notes,
  ); // <-- not 'reject'
}
