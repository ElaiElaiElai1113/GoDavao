// lib/data/chat_subscription_service.dart

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatSubscriptionService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;
  final Map<String, int> unreadCounts = {};

  /// Call once at app startup
  void start() {
    _channel =
        _supabase
            .channel('messages_all')
            .onPostgresChanges(
              schema: 'public',
              table: 'ride_messages',
              event: PostgresChangeEvent.insert,
              callback: (payload) {
                final matchId = payload.newRecord['ride_match_id'] as String;
                if (_currentOpenChatId != matchId) {
                  unreadCounts[matchId] = (unreadCounts[matchId] ?? 0) + 1;
                  notifyListeners();
                }
              },
            )
            .subscribe();
  }

  String? _currentOpenChatId;

  /// Tell the service which chat is currently open
  void setOpenChat(String? matchId) {
    _currentOpenChatId = matchId;
    if (matchId != null) markRead(matchId);
  }

  /// Clears the unread count for a chat
  void markRead(String matchId) {
    if (unreadCounts.containsKey(matchId)) {
      unreadCounts.remove(matchId);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
    }
    super.dispose();
  }
}
