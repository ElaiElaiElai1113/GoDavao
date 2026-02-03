import 'package:supabase_flutter/supabase_flutter.dart';

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

    // Cache to avoid duplicate lookups
    final userCache = <String, Map<String, String>>{};

    await for (final rows in stream) {
      final enriched = <Map<String, dynamic>>[];

      for (final row in rows) {
        final data = Map<String, dynamic>.from(row);
        final userId = data['user_id']?.toString();

        if (userId != null) {
          if (!userCache.containsKey(userId)) {
            final user = await _fetchUserDetails(userId);
            if (user != null) userCache[userId] = user;
          }

          final cached = userCache[userId];
          data['name'] = cached?['name'] ?? 'Unknown';
          data['phone'] = cached?['phone'] ?? '—';
        } else {
          data['name'] = 'Unknown';
          data['phone'] = '—';
        }

        enriched.add(data);
      }

      yield enriched;
    }
  }

  // Helper to fetch both name and phone
  Future<Map<String, String>?> _fetchUserDetails(String userId) async {
    final user =
        await client
            .from('users')
            .select('name, phone')
            .eq('id', userId)
            .maybeSingle();

    if (user == null) return null;

    return {
      'name': (user['name'] ?? '').toString(),
      'phone': (user['phone'] ?? '').toString(),
    };
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

  // -------------------- Fetch Verification Files --------------------

  Future<Map<String, dynamic>?> fetchVerificationFiles(String requestId) async {
    final result =
        await client
            .from('verification_requests')
            .select('id_front_key, id_back_key, selfie_key')
            .eq('id', requestId)
            .maybeSingle();

    if (result == null) return null;

    return {
      'id_front_key': result['id_front_key'],
      'id_back_key': result['id_back_key'],
      'selfie_key': result['selfie_key'],
    };
  }

  // -------------------- Queries --------------------

  Future<List<Map<String, dynamic>>> fetch({String? status}) async {
    final List<dynamic> data =
        status == null
            ? await client
                .from('verification_requests')
                .select('*, users:users(id, role, verification_status)')
                .order('created_at', ascending: false)
            : await client
                .from('verification_requests')
                .select('*, users:users(id, role, verification_status)')
                .eq('status', status)
                .order('created_at', ascending: false);

    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> getById(String requestId) async {
    return await client
        .from('verification_requests')
        .select('*, users:users(id, role, verification_status)')
        .eq('id', requestId)
        .maybeSingle();
  }

  // -------------------- Actions (via RPC) --------------------

  Future<void> _process({
    required String requestId,
    required String actionEnum,
    String? notes,
  }) async {
    final cleanedNotes = (notes?.trim().isEmpty ?? true) ? null : notes!.trim();

    await client.rpc<void>(
      'process_verification_request',
      params: {
        'p_request_id': requestId,
        'p_action': actionEnum,
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
  );
}
