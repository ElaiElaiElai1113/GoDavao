// lib/features/conversations/presentation/conversations_list.dart

import 'package:flutter/material.dart';
import 'package:godavao/features/chat/data/chat_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../chat/presentation/chat_page.dart';

class ConversationsList extends StatefulWidget {
  const ConversationsList({super.key});

  @override
  State<ConversationsList> createState() => _ConversationsListState();
}

class _ConversationsListState extends State<ConversationsList> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _matches = [];

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    final user = supabase.auth.currentUser!;
    final rows = await supabase
        .from('ride_matches')
        .select('id, other_user_name, last_message, updated_at')
        .eq('passenger_id', user.id)
        .order('updated_at', ascending: false);
    setState(() => _matches = List<Map<String, dynamic>>.from(rows));
  }

  @override
  Widget build(BuildContext context) {
    final chatSvc = context.watch<ChatSubscriptionService>();
    return ListView.builder(
      itemCount: _matches.length,
      itemBuilder: (_, i) {
        final m = _matches[i];
        final unread = chatSvc.unreadCounts[m['id']] ?? 0;
        return ListTile(
          title: Text(m['other_user_name'] as String? ?? 'Unknown'),
          subtitle: Text(m['last_message'] as String? ?? ''),
          trailing:
              unread > 0
                  ? CircleAvatar(
                    radius: 10,
                    child: Text('$unread', style: TextStyle(fontSize: 12)),
                  )
                  : null,
          onTap: () {
            chatSvc.setOpenChat(m['id'] as String);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatPage(matchId: m['id'] as String),
              ),
            );
          },
        );
      },
    );
  }
}
