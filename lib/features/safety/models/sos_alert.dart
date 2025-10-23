class SosAlert {
  final String id;
  final String userId;
  final double lat;
  final double lng;
  final String? rideId;
  final DateTime createdAt;
  final bool notified;

  SosAlert({
    required this.id,
    required this.userId,
    required this.lat,
    required this.lng,
    required this.createdAt,
    required this.notified,
    this.rideId,
  });

  factory SosAlert.fromMap(Map<String, dynamic> m) => SosAlert(
    id: m['id'] as String,
    userId: m['user_id'] as String,
    lat: (m['lat'] as num).toDouble(),
    lng: (m['lng'] as num).toDouble(),
    rideId: m['ride_id'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
    notified: (m['notified'] as bool?) ?? false,
  );
}
