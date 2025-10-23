import 'dart:async';
import 'package:flutter/material.dart';
import 'package:godavao/features/chat/data/chat_subscription_service.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../main.dart';

class ChatPage extends StatefulWidget {
  final String matchId;
  const ChatPage({required this.matchId, super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with AutomaticKeepAliveClientMixin<ChatPage>, RouteAware {
  final _supabase = Supabase.instance.client;
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<ChatMessage> _messages = [];
  RealtimeChannel? _pgChannel;
  RealtimeChannel? _bcChannel;
  bool _otherTyping = false;
  Timer? _typingTimer;

  bool _didSubscribeRoute = false;
  String? _rideStatus; // will hold ride status like accepted, cancelled, completed
    // OLD:
    // bool get _isChatLocked =>
    //     _rideStatus == 'cancelled' || _rideStatus == 'completed';

    // NEW:
    bool get _isChatLocked =>
      const {'cancelled','canceled','declined','completed'}.contains(_rideStatus);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _fetchHistory();
    _listenPostgres();
    _listenBroadcast();
    _markSeen();
    _fetchRideStatus();
    _listenRideStatus();
    
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didSubscribeRoute) {
      routeObserver.subscribe(this, ModalRoute.of(context)!);
      context.read<ChatSubscriptionService>().setOpenChat(widget.matchId);
      _didSubscribeRoute = true;
    }
  }

  @override
  void dispose() {
    if (_didSubscribeRoute) {
      routeObserver.unsubscribe(this);
      context.read<ChatSubscriptionService>().setOpenChat(null);
    }
    if (_pgChannel != null) Supabase.instance.client.removeChannel(_pgChannel!);
    if (_bcChannel != null) Supabase.instance.client.removeChannel(_bcChannel!);
    _typingTimer?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    _fetchHistory();
    super.didPopNext();
  }

  Future<void> _fetchHistory() async {
    final rows = await _supabase
        .from('ride_messages')
        .select('id, sender_id, content, created_at, seen_at')
        .eq('ride_match_id', widget.matchId)
        .order('created_at', ascending: true);
    setState(() {
      _messages =
          (rows as List)
              .map((m) => ChatMessage.fromMap(m as Map<String, dynamic>))
              .toList();
    });
    _scrollToBottom();
  }

  void _listenPostgres() {
    _pgChannel =
        _supabase
            .channel('messages:${widget.matchId}')
            .onPostgresChanges(
              schema: 'public',
              table: 'ride_messages',
              event: PostgresChangeEvent.insert,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'ride_match_id',
                value: widget.matchId,
              ),
              callback: (p) {
                final msg = ChatMessage.fromMap(Map.from(p.newRecord));
                setState(() => _messages.add(msg));
                _scrollToBottom();
              },
            )
            .subscribe();
  }

  void _listenBroadcast() {
    _bcChannel =
        _supabase
            .channel('room:${widget.matchId}')
            .onBroadcast(
              event: 'typing',
              callback: (payload) {
                final me = _supabase.auth.currentUser?.id;
                if (payload['sender_id'] != me) {
                  setState(() => _otherTyping = true);
                  _typingTimer?.cancel();
                  _typingTimer = Timer(
                    const Duration(seconds: 3),
                    () => setState(() => _otherTyping = false),
                  );
                }
              },
            )
            .subscribe();
  }

  Future<void> _markSeen() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    await _supabase
        .from('ride_messages')
        .update({'seen_at': DateTime.now().toIso8601String()})
        .eq('ride_match_id', widget.matchId)
        .neq('sender_id', user.id);
  }
Future<void> _fetchRideStatus() async {
  try {
    final res = await _supabase
        .from('ride_matches')
        .select('status')
        .eq('id', widget.matchId)
        .maybeSingle();
    if (mounted) {
      setState(() => _rideStatus = res?['status']);
    }
  } catch (e) {
    print('Failed to fetch ride status: $e');
  }
}

void _listenRideStatus() {
  _supabase
      .from('ride_matches:id=eq.${widget.matchId}')
      .stream(primaryKey: ['id'])
      .listen((rows) {
    if (rows.isNotEmpty) {
      final s = rows.first['status'] as String?;
      if (mounted) setState(() => _rideStatus = s);
    }
  });
}

  Future<void> _sendMessage() async {
  if (_isChatLocked) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Chat is locked because the ride has been cancelled, declined, or completed.',
        ),
      ),
    );
    return;
  }

  final txt = _textCtrl.text.trim();
  if (txt.isEmpty) return;
  final user = _supabase.auth.currentUser;
  if (user == null) return;

  final temp = ChatMessage(
    id: UniqueKey().toString(),
    senderId: user.id,
    content: txt,
    createdAt: DateTime.now(),
    status: MessageStatus.sending,
  );

  setState(() => _messages.add(temp));
  _scrollToBottom();
  _textCtrl.clear();

  try {
    final ins = await _supabase
        .from('ride_messages')
        .insert({
          'ride_match_id': widget.matchId,
          'sender_id': user.id,
          'content': txt,
        })
        .select('id, sender_id, content, created_at')
        .maybeSingle();

    if (ins != null) {
      setState(() {
        temp.status = MessageStatus.sent;
        final idx = _messages.indexWhere((m) => m.id == temp.id);
        if (idx != -1) _messages[idx] = ChatMessage.fromMap(Map.from(ins));
      });
    }
  } on PostgrestException catch (e) {
    if (e.code == '45000' ||
        (e.message ?? '').toLowerCase().contains('cannot send messages')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chat is locked because the ride has been cancelled or completed.',
          ),
        ),
      );
      setState(() => _rideStatus = 'cancelled');
    } else {
      setState(() => temp.status = MessageStatus.failed);
    }
  } catch (_) {
    setState(() => temp.status = MessageStatus.failed);
  }
}

  void _onTyping(String _) {
    final me = _supabase.auth.currentUser?.id;
    if (me != null) {
      _bcChannel?.sendBroadcastMessage(
        event: 'typing',
        payload: {'sender_id': me},
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 50,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final me = _supabase.auth.currentUser?.id;

    // group by date
    final grouped = <DateTime, List<ChatMessage>>{};
    for (var m in _messages) {
      final d = DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
      grouped.putIfAbsent(d, () => []).add(m);
    }
    final dates = grouped.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          if (_isChatLocked)
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    margin: const EdgeInsets.only(top: 6),
    decoration: BoxDecoration(
      color: Colors.amber.shade50,
      border: Border.all(color: Colors.amber.shade200),
    ),
    child: const Text(
      'This conversation is read-only because the ride was cancelled, declined, or completed.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12),
    ),
  ),
          Expanded(
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(8),
              children: [
                for (var date in dates) ...[
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        DateFormat('MMM d, yyyy').format(date),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  for (var msg in grouped[date]!) _buildBubble(msg, me),
                ],
                if (_otherTyping)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'is typing…',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          _isChatLocked
    ? Container(
        padding: const EdgeInsets.all(16),
        color: Colors.grey.shade100,
        width: double.infinity,
        child: const Text(
          'Chat unavailable — this ride has been cancelled, declined, or completed.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      )
    : Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textCtrl,
                onChanged: _onTyping,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration.collapsed(
                  hintText: 'Type a message',
                ),
                onSubmitted: (_) => _sendMessage(),
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

  Widget _buildBubble(ChatMessage msg, String? me) {
    final isMe = msg.senderId == me;
    final time = DateFormat('h:mm a').format(msg.createdAt);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  isMe
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              msg.content,
              style: TextStyle(color: isMe ? Colors.white : Colors.black87),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                time,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              if (isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    msg.status == MessageStatus.sent
                        ? Icons.check
                        : msg.status == MessageStatus.failed
                        ? Icons.error_outline
                        : Icons.access_time,
                    size: 12,
                    color: Colors.grey,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum MessageStatus { sending, sent, failed }

class ChatMessage {
  String id, senderId, content;
  DateTime createdAt;
  MessageStatus status;
  DateTime? seenAt;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.status = MessageStatus.sent,
    this.seenAt,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
    id: m['id'].toString(),
    senderId: m['sender_id'] as String,
    content: m['content'] as String,
    createdAt: DateTime.parse(m['created_at'] as String),
    status: MessageStatus.sent,
    seenAt:
        m['seen_at'] != null ? DateTime.parse(m['seen_at'] as String) : null,
  );
}
