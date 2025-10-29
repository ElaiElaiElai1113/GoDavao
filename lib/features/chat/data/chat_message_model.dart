enum MessageStatus { sending, delivered, seen, failed }

class ChatMessage {
  final String id;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final DateTime? seenAt;
  final MessageStatus status;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.seenAt,
    this.status = MessageStatus.delivered,
  });

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? content,
    DateTime? createdAt,
    DateTime? seenAt,
    MessageStatus? status,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      seenAt: seenAt ?? this.seenAt,
      status: status ?? this.status,
    );
  }

  factory ChatMessage.fromMap(Map<String, dynamic> m) {
    final created = DateTime.parse(m['created_at'] as String).toLocal();
    final seenStr = m['seen_at'] as String?;
    final seen = seenStr != null ? DateTime.parse(seenStr).toLocal() : null;

    // Default to delivered if it’s in the DB; mark as seen when seenAt exists.
    final status = seen != null ? MessageStatus.seen : MessageStatus.delivered;

    return ChatMessage(
      id: m['id'].toString(),
      senderId: m['sender_id'] as String,
      content: m['content'] as String,
      createdAt: created,
      seenAt: seen,
      status: status,
    );
  }
}
