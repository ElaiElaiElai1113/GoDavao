import 'package:supabase_flutter/supabase_flutter.dart';

class RatingsService {
  final SupabaseClient supabase;
  RatingsService(this.supabase);

  Future<Map<String, dynamic>?> getExistingRating({
    required String rideId,
    required String raterUserId,
    required String rateeUserId,
  }) async {
    final res =
        await supabase
            .from('ratings')
            .select()
            .eq('ride_id', rideId)
            .eq('rater_user_id', raterUserId)
            .eq('ratee_user_id', rateeUserId)
            .limit(1)
            .maybeSingle();
    return res;
  }

  Future<void> submitRating({
    required String rideId,
    required String raterUserId,
    required String rateeUserId,
    required String rateeRole, // 'driver' | 'passenger'
    required int score, // 1..5
    String? comment,
  }) async {
    await supabase.from('ratings').insert({
      'ride_id': rideId,
      'rater_user_id': raterUserId,
      'ratee_user_id': rateeUserId,
      'ratee_role': rateeRole,
      'score': score,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment,
    });
  }

  Future<Map<String, dynamic>?> fetchUserAggregate(String userId) async {
    final res =
        await supabase
            .from('users')
            .select('avg_rating,rating_count')
            .eq('id', userId)
            .maybeSingle();
    return res;
  }
}
