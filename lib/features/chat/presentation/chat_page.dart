import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatPage extends StatefulWidget {
  final String matchId;
  const ChatPage({required this.matchId, super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final supabase = Supabase.instance.client;
  final _textCtrl = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _messagesChannel;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _subscribeRealtime();
  }

  Future<void> _fetchHistory() async {
    final data = await supabase
        .from('ride_messages')
        .select('id, sender_id, content, created_at')
        .eq('ride_match_id', widget.matchId)
        .order('created_at', ascending: true);
    setState(() {
      _messages.clear();
      _messages.addAll((data as List).cast<Map<String, dynamic>>());
    });
  }

  void _subscribeRealtime() {
    // create & store the actual RealtimeChannel
    _messagesChannel =
        supabase
            .channel('public:ride_messages') // channel identifier
            .onPostgresChanges(
              schema: 'public',
              table: 'ride_messages',
              event: PostgresChangeEvent.insert,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'ride_match_id',
                value: widget.matchId,
              ),
              callback: (payload) {
                final msg = Map<String, dynamic>.from(payload.newRecord!);
                setState(() {
                  _messages.add(msg);
                });
              },
            )
            .subscribe();
  }

  Future<void> _sendMessage() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase.from('ride_messages').insert({
      'ride_match_id': widget.matchId,
      'sender_id': user.id,
      'content': text,
    });
    _textCtrl.clear();
  }

  @override
  void dispose() {
    // remove the RealtimeChannel, not the String
    if (_messagesChannel != null) {
      supabase.removeChannel(_messagesChannel!);
    }
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = supabase.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _messages.length,
              itemBuilder: (ctx, i) {
                final msg = _messages[i];
                final isMe = msg['sender_id'] == me;
                return Align(
                  alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          isMe
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      msg['content'] as String,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration.collapsed(
                      hintText: 'Type a message',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
