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

  Stream<List<Map<String, dynamic>>> watchPending() async* {
    final stream = client
        .from('verification_requests')
        .stream(primaryKey: ['id'])
        .eq('status', VerificationStatus.pending);

    final nameCache = <String, String>{};

    await for (final rows in stream) {
      final result = <Map<String, dynamic>>[];

      for (final row in rows) {
        final data = Map<String, dynamic>.from(row);
        final userId = data['user_id']?.toString();

        if (userId != null) {
          // Get from cache or fetch from users table
          nameCache[userId] ??= (await _fetchName(userId))!;
          data['name'] = nameCache[userId];
        }

        result.add(data);
      }

      yield result;
    }
  }

  // Helper function
  Future<String?> _fetchName(String userId) async {
    final user =
        await client
            .from('users')
            .select('name')
            .eq('id', userId)
            .maybeSingle();
    return user?['name'] as String?;
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
