import 'dart:convert';
import 'package:http/http.dart' as http;

/// Very small in-memory cache
class _GeoCache {
  final _map = <String, String>{};
  String? get(double lat, double lng) => _map['$lat,$lng'];
  void set(double lat, double lng, String value) => _map['$lat,$lng'] = value;
}

final _cache = _GeoCache();

/// Reverse geocode using OpenStreetMap Nominatim.
/// Respect their usage policy: add a proper User-Agent and avoid spamming.
Future<String> reverseGeocodeText(double lat, double lng) async {
  // Cache hit?
  final cached = _cache.get(lat, lng);
  if (cached != null) return cached;

  final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
    'format': 'jsonv2',
    'lat': lat.toString(),
    'lon': lng.toString(),
    'zoom': '18',
    'addressdetails': '1',
  });

  try {
    final res = await http.get(
      uri,
      headers: {
        // REQUIRED: identify your app; replace email/URL with your contact
        'User-Agent': 'GoDavao/1.0 (https://godavao.app; support@godavao.app)',
        'Accept': 'application/json',
      },
    );

    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final addr = (data['address'] as Map?)?.cast<String, dynamic>() ?? {};

    // Build a concise label: road, suburb/barangay, city/municipality
    final parts =
        <String>[
          if ((addr['road'] ?? '').toString().isNotEmpty) addr['road'],
          if ((addr['suburb'] ?? '').toString().isNotEmpty) addr['suburb'],
          if ((addr['neighbourhood'] ?? '').toString().isNotEmpty)
            addr['neighbourhood'],
          if ((addr['village'] ?? '').toString().isNotEmpty) addr['village'],
          if ((addr['city'] ?? '').toString().isNotEmpty) addr['city'],
          if ((addr['town'] ?? '').toString().isNotEmpty) addr['town'],
          if ((addr['municipality'] ?? '').toString().isNotEmpty)
            addr['municipality'],
        ].whereType<String>().toList();

    final label =
        parts.isNotEmpty
            ? parts.take(3).join(', ')
            : (data['display_name'] as String? ?? 'Unknown');

    _cache.set(lat, lng, label);
    return label;
  } catch (_) {
    return 'Unknown';
  }
}
