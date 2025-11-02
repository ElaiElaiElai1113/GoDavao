import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  final SupabaseClient _sb;
  NotificationService(this._sb);

  /// Realtime stream of notifications for a user (newest first)
  Stream<List<Map<String, dynamic>>> streamForUser(String userId) {
    return _sb
        .from('notifications:user_id=eq.$userId')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  /// Mark a single notification as read (uses your RPC)
  Future<void> markRead(String id) async {
    await _sb.rpc('mark_notification_read', params: {'p_id': id});
  }

  /// Mark all as read (uses your RPC)
  Future<void> markAllRead() async {
    await _sb.rpc('mark_all_notifications_read');
  }

  /// Get unread count (SDK-safe: no FetchOptions/count API used)
  Future<int> unreadCount(String userId) async {
    final rows = await _sb
        .from('notifications')
        .select('id') // only fetch ids
        .eq('user_id', userId)
        .filter('read_at', 'is', null); // instead of .is_()

    // rows is a List<dynamic>; return its length safely
    if (rows is List) return rows.length;
    return 0;
  }
}
