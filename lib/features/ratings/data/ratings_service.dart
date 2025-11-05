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
    List<String>? tags,
  }) async {
    await supabase.from('ratings').insert({
      'ride_id': rideId,
      'rater_user_id': raterUserId,
      'ratee_user_id': rateeUserId,
      'ratee_role': rateeRole,
      'score': rating,
      'comment': (comment?.isEmpty ?? true) ? null : comment,
      'tags': tags ?? <String>[],
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
    return row == null ? null : Map<String, dynamic>.from(row as Map);
  }

  // 👇 safer version: get all scores for that user and compute in Dart
  Future<Map<String, dynamic>> fetchUserAggregate(String userId) async {
    final rows = await supabase
        .from('ratings')
        .select('score')
        .eq('ratee_user_id', userId);

    if (rows is! List || rows.isEmpty) {
      return {'avg_rating': null, 'rating_count': 0};
    }

    double sum = 0;
    for (final r in rows) {
      sum += (r['score'] as num).toDouble();
    }
    final count = rows.length;
    final avg = sum / count;
    return {'avg_rating': avg, 'rating_count': count};
  }

  Future<Map<int, int>> fetchDistribution(
    String userId, {
    int sample = 200,
  }) async {
    final rows = await supabase
        .from('ratings')
        .select('score')
        .eq('ratee_user_id', userId)
        .order('created_at', ascending: false)
        .limit(sample);

    final dist = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in rows as List) {
      final n = (r['score'] as num).toInt();
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
        .select('score, comment, tags, created_at, rater_user_id')
        .eq('ratee_user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
