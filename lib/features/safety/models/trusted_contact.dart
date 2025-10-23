// lib/models/trusted_contact.dart
class TrustedContact {
  final String id;
  final String userId;
  final String name;
  final String? phone;
  final String? email;
  final bool notifyBySms;
  final bool notifyByEmail;

  TrustedContact({
    required this.id,
    required this.userId,
    required this.name,
    this.phone,
    this.email,
    this.notifyBySms = true,
    this.notifyByEmail = false,
  });

  factory TrustedContact.fromMap(Map<String, dynamic> m) => TrustedContact(
    id: m['id'] as String,
    userId: m['user_id'] as String,
    name: (m['name'] as String).trim(),
    phone: (m['phone'] as String?)?.trim(),
    email: (m['email'] as String?)?.trim(),
    notifyBySms: (m['notify_by_sms'] as bool?) ?? true,
    notifyByEmail: (m['notify_by_email'] as bool?) ?? false,
  );
}
