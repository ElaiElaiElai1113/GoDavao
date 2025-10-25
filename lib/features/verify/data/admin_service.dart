import 'package:supabase_flutter/supabase_flutter.dart';

class VerificationStatus {
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
}

class AdminVerificationService {
  AdminVerificationService(this.client);
  final SupabaseClient client;

  static const _bucket = 'verifications';

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

  Future<List<Map<String, dynamic>>> fetch({String? status}) async {
    final List data =
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

  // -------------------- Documents --------------------

  /// Signed URL with fallback to public URL (if bucket/object is public or policy allows).
  Future<String> _signedOrPublicUrl(
    String bucket,
    String key, {
    Duration ttl = const Duration(minutes: 30),
  }) async {
    if (key.isEmpty) return '';
    try {
      final signed = await client.storage
          .from(bucket)
          .createSignedUrl(key, ttl.inSeconds);
      return signed;
    } catch (_) {
      return client.storage.from(bucket).getPublicUrl(key);
    }
  }

  String _detectMime(String key) {
    final lower = key.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp')) {
      return 'image/*';
    }
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  /// Fetch the latest submission docs for a given user.
  /// Returns a list of {type, url, key, mime}.
  Future<List<Map<String, dynamic>>> fetchSubmissionDocsForUser(
    String userId,
  ) async {
    final req =
        await client
            .from('verification_requests')
            .select(
              'id, id_type, id_front_key, id_back_key, selfie_key, driver_license_key, orcr_key, updated_at',
            )
            .eq('user_id', userId)
            .order('updated_at', ascending: false)
            .limit(1)
            .maybeSingle();

    return _mapRequestToDocs(req);
  }

  /// Optional: fetch by request id (useful on a details screen).
  Future<List<Map<String, dynamic>>> fetchSubmissionDocsByRequestId(
    String requestId,
  ) async {
    final req =
        await client
            .from('verification_requests')
            .select(
              'id, id_type, id_front_key, id_back_key, selfie_key, driver_license_key, orcr_key, updated_at',
            )
            .eq('id', requestId)
            .maybeSingle();

    return _mapRequestToDocs(req);
  }

  List<Map<String, dynamic>> _mapRequestToDocs(Map<String, dynamic>? req) {
    if (req == null) return const [];

    final mapKeyToType = <String, String>{
      'id_front_key': 'id_front',
      'id_back_key': 'id_back',
      'selfie_key': 'selfie',
      'driver_license_key': 'license',
      'orcr_key': 'vehicle_orcr',
    };

    final out = <Map<String, dynamic>>[];

    for (final entry in mapKeyToType.entries) {
      final key = (req[entry.key] ?? '').toString();
      if (key.isEmpty) continue;

      final mime = _detectMime(key);

      out.add({
        'type': entry.value,
        'key': key,
        'mime': mime,
        // lazily fetch a signed/public URL when needed
        'urlProvider': () => _signedOrPublicUrl(_bucket, key),
      });
    }

    return out;
  }

  // -------------------- Actions (via RPC) --------------------

  Future<void> _process({
    required String requestId,
    required String actionEnum,
    String? notes,
  }) async {
    final cleanedNotes = (notes?.trim().isEmpty ?? true) ? null : notes!.trim();

    await client.rpc(
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

  // -------------------- Helpers --------------------

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
}
