class TrustedContact {
  final String id;
  final String userId;
  final String name;
  final String phone;
  final String? email;
  final DateTime createdAt;

  TrustedContact({
    required this.id,
    required this.userId,
    required this.name,
    required this.phone,
    this.email,
    required this.createdAt,
  });

  factory TrustedContact.fromMap(Map<String, dynamic> m) => TrustedContact(
    id: m['id'] as String,
    userId: m['user_id'] as String,
    name: m['name'] as String,
    phone: m['phone'] as String,
    email: m['email'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  Map<String, dynamic> toInsert() => {
    'name': name,
    'phone': phone,
    if (email != null) 'email': email,
  };
}
