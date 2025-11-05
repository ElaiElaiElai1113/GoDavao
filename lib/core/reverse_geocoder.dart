import 'package:geocoding/geocoding.dart';

class _GeoCache {
  final _map = <String, String>{};
  String? get(String key) => _map[key];
  void set(String key, String value) => _map[key] = value;
}

final _cache = _GeoCache();

Future<String> reverseGeocodeText(double lat, double lng) async {
  final key = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
  final hit = _cache.get(key);
  if (hit != null) return hit;

  try {
    final placemarks = await placemarkFromCoordinates(lat, lng);
    if (placemarks.isEmpty) return 'Unknown location';

    final p = placemarks.first;

    final parts = <String>[];
    final street = p.street;
    final subLocality = p.subLocality;
    final locality = p.locality;

    if (street != null && street.isNotEmpty) {
      parts.add(street);
    }
    if (subLocality != null && subLocality.isNotEmpty) {
      parts.add(subLocality);
    }
    if (locality != null && locality.isNotEmpty) {
      parts.add(locality);
    }

    final label = parts.isNotEmpty ? parts.join(', ') : 'Unknown location';

    if (label != 'Unknown location') {
      _cache.set(key, label);
    }

    return label;
  } catch (_) {
    return 'Unknown location';
  }
}
