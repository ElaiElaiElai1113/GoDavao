// lib/common/tutorial/tutorial_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class TutorialService {
  static const _kDashboardSeen = 'dashboard_tutorial_seen';

  static Future<bool> getDashboardSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kDashboardSeen) ?? false;
  }

  static Future<void> setDashboardSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDashboardSeen, true);
  }

  // For testing or to re-show tutorial:
  static Future<void> resetDashboardSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDashboardSeen);
  }
}
