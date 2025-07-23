import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../presentation/chat_page.dart';

class ChatMessagesService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Holds in‑memory history per chat
  final Map<String, List<ChatMessage>> _history = {};

  /// Tracks if we already subscribed realtime for a chat
  final Set<String> _realtimeSubscribed = {};

  List<ChatMessage> messagesFor(String chatId) => _history[chatId] ?? [];

  /// Fetches from DB once
  Future<void> fetchHistory(String chatId) async {
    final rows = await _supabase
        .from('ride_messages')
        .select('id, sender_id, content, created_at')
        .eq('ride_match_id', chatId)
        .order('created_at', ascending: true);
    _history[chatId] =
        (rows as List)
            .map((m) => ChatMessage.fromMap(m as Map<String, dynamic>))
            .toList();
    notifyListeners();
    _ensureRealtime(chatId);
  }

  /// Sets up realtime listener exactly once
  void _ensureRealtime(String chatId) {
    if (_realtimeSubscribed.contains(chatId)) return;
    _realtimeSubscribed.add(chatId);

    _supabase
        .channel('messages:$chatId')
        .onPostgresChanges(
          schema: 'public',
          table: 'ride_messages',
          event: PostgresChangeEvent.insert,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ride_match_id',
            value: chatId,
          ),
          callback: (payload) {
            final msg = ChatMessage.fromMap(
              Map<String, dynamic>.from(payload.newRecord!),
            );
            _history.putIfAbsent(chatId, () => []).add(msg);
            notifyListeners();
          },
        )
        .subscribe();
  }

  /// Call this when sending so UI is optimistic
  void addTempMessage(String chatId, ChatMessage temp) {
    _history.putIfAbsent(chatId, () => []).add(temp);
    notifyListeners();
  }

  /// Call this to replace the temp with real DB record
  void replaceTempMessage(String chatId, String tempId, ChatMessage real) {
    final list = _history[chatId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == tempId);
    if (idx != -1) {
      list[idx] = real;
      notifyListeners();
    }
  }
}
