import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class WeatherInfo {
  final bool isRaining;
  final String description;

  WeatherInfo({required this.isRaining, required this.description});
}

class WeatherService {
  static Future<WeatherInfo> getWeatherAt(LatLng location) async {
    final lat = location.latitude;
    final lon = location.longitude;
    final url =
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=precipitation,weathercode';

    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('Failed to fetch weather');
      final data = jsonDecode(res.body);

      final weatherCode = data['current']['weathercode'] ?? 0;
      final precipitation = (data['current']['precipitation'] ?? 0.0) as num;

      final raining =
          precipitation > 0 ||
          [51, 53, 55, 61, 63, 65, 80, 81, 82].contains(weatherCode);

      String desc;
      if (raining) {
        desc = "Light Rain";
      } else if ([0].contains(weatherCode)) {
        desc = "Clear Sky";
      } else if ([1, 2].contains(weatherCode)) {
        desc = "Partly Cloudy";
      } else if ([3, 45, 48].contains(weatherCode)) {
        desc = "Cloudy";
      } else {
        desc = "Unknown";
      }

      return WeatherInfo(isRaining: raining, description: desc);
    } catch (e) {
      return WeatherInfo(isRaining: false, description: 'Unavailable');
    }
  }
}
