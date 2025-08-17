import 'package:supabase_flutter/supabase_flutter.dart';

class RatingsService {
  final SupabaseClient supabase;
  RatingsService(this.supabase);

  Future<void> submitRating({
    required String rideId,
    required String raterUserId,
    required String rateeUserId,
    required int rating, // 1..5
    required String rateeRole, // 'driver' | 'passenger'
    String? comment,
    List<String>? tags, // optional feedback tags
  }) async {
    await supabase.from('ratings').insert({
      'ride_id': rideId,
      'rater_user_id': raterUserId,
      'ratee_user_id': rateeUserId,
      'rating': rating,
      'comment': comment,
      'tags': tags ?? <String>[],
      'ratee_role': rateeRole,
    });
  }

  Future<Map<String, dynamic>?> getExistingRating({
    required String rideId,
    required String raterUserId,
    required String rateeUserId,
  }) async {
    final row =
        await supabase
            .from('ratings')
            .select('id')
            .eq('ride_id', rideId)
            .eq('rater_user_id', raterUserId)
            .eq('ratee_user_id', rateeUserId)
            .maybeSingle();
    return (row == null) ? null : Map<String, dynamic>.from(row as Map);
  }

  Future<Map<String, dynamic>> fetchUserAggregate(String userId) async {
    // avg + count
    final res = await supabase.rpc(
      'void',
    ) /* dummy to keep type hints happy */; // not used
    final rows = await supabase
        .from('ratings')
        .select('rating')
        .eq('ratee_user_id', userId);
    double sum = 0;
    int cnt = 0;
    for (final r in rows as List) {
      sum += (r['rating'] as num).toDouble();
      cnt++;
    }
    final avg = cnt == 0 ? null : sum / cnt;
    return {'avg_rating': avg, 'rating_count': cnt};
  }

  Future<Map<int, int>> fetchDistribution(
    String userId, {
    int sample = 200,
  }) async {
    final rows = await supabase
        .from('ratings')
        .select('rating')
        .eq('ratee_user_id', userId)
        .order('created_at', ascending: false)
        .limit(sample);
    final dist = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in rows as List) {
      final n = r['rating'] as int;
      if (dist.containsKey(n)) dist[n] = dist[n]! + 1;
    }
    return dist;
  }

  Future<List<Map<String, dynamic>>> fetchRecentFeedback(
    String userId, {
    int limit = 20,
  }) async {
    final rows = await supabase
        .from('ratings')
        .select('rating, comment, tags, created_at, rater_user_id')
        .eq('ratee_user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
