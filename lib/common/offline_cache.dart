import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:godavao/common/app_logger.dart';

/// Offline cache service for storing data locally.
///
/// Supports:
/// - Time-based cache expiration
/// - JSON serialization
/// - Type-safe getters/setters
/// - Cache statistics
final class OfflineCache {
  OfflineCache._();

  static SharedPreferences? _prefs;
  static bool _initialized = false;

  // Cache duration constants
  static const Duration defaultCacheDuration = Duration(hours: 1);
  static const Duration shortCacheDuration = Duration(minutes: 5);
  static const Duration longCacheDuration = Duration(days: 7);

  // Cache key prefixes
  static const String _prefix = 'cache_';
  static const String _timestampPrefix = 'cache_ts_';

  /// Initialize the cache service
  static Future<void> init() async {
    if (_initialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
      AppLogger.i('OfflineCache initialized');
    } catch (e) {
      AppLogger.e('Failed to initialize OfflineCache', e);
      rethrow;
    }
  }

  /// Store a value in cache with optional expiration
  static Future<void> set<T>(
    String key,
    T value, {
    Duration? duration,
  }) async {
    _ensureInitialized();

    try {
      final jsonString = _encode(value);
      final timestamp = DateTime.now().toIso8601String();

      await _prefs!.setString('$_prefix$key', jsonString);
      await _prefs!.setString(
        '$_timestampPrefix$key',
        timestamp,
      );

      if (duration != null) {
        final expiry = DateTime.now().add(duration).toIso8601String();
        await _prefs!.setString('$_timestampPrefix${key}_expiry', expiry);
      }

      AppLogger.d('Cached: $key');
    } catch (e) {
      AppLogger.e('Failed to cache $key', e);
    }
  }

  /// Get a value from cache
  static T? get<T>(String key) {
    _ensureInitialized();

    try {
      // Check if cache is expired
      if (_isExpired(key)) {
        invalidate(key);
        return null;
      }

      final jsonString = _prefs!.getString('$_prefix$key');
      if (jsonString == null) return null;

      return _decode<T>(jsonString);
    } catch (e) {
      AppLogger.e('Failed to get cached value: $key', e);
      return null;
    }
  }

  /// Check if a key exists and is not expired
  static bool has(String key) {
    _ensureInitialized();

    if (_isExpired(key)) {
      invalidate(key);
      return false;
    }

    return _prefs!.containsKey('$_prefix$key');
  }

  /// Invalidate a specific cache entry
  static Future<void> invalidate(String key) async {
    _ensureInitialized();

    try {
      await _prefs!.remove('$_prefix$key');
      await _prefs!.remove('$_timestampPrefix$key');
      await _prefs!.remove('$_timestampPrefix${key}_expiry');
      AppLogger.d('Invalidated cache: $key');
    } catch (e) {
      AppLogger.e('Failed to invalidate $key', e);
    }
  }

  /// Clear all cached data
  static Future<void> clear() async {
    _ensureInitialized();

    try {
      final keys = _prefs!.getKeys();
      final cacheKeys = keys.where((k) => k.startsWith(_prefix)).toList();

      for (final key in cacheKeys) {
        await _prefs!.remove(key);
      }

      // Also remove timestamps
      final tsKeys = keys.where((k) => k.startsWith(_timestampPrefix)).toList();
      for (final key in tsKeys) {
        await _prefs!.remove(key);
      }

      AppLogger.i('Cleared all cache');
    } catch (e) {
      AppLogger.e('Failed to clear cache', e);
    }
  }

  /// Clear expired cache entries
  static Future<int> clearExpired() async {
    _ensureInitialized();

    try {
      final keys = _prefs!.getKeys();
      final cacheKeys = keys
          .where((k) => k.startsWith(_timestampPrefix) && !k.endsWith('_expiry'))
          .toList();

      int cleared = 0;

      for (final tsKey in cacheKeys) {
        final key = tsKey.substring(_timestampPrefix.length);
        if (_isExpired(key)) {
          await invalidate(key);
          cleared++;
        }
      }

      if (cleared > 0) {
        AppLogger.i('Cleared $cleared expired cache entries');
      }

      return cleared;
    } catch (e) {
      AppLogger.e('Failed to clear expired cache', e);
      return 0;
    }
  }

  /// Get cache statistics
  static Map<String, dynamic> getStats() {
    _ensureInitialized();

    final keys = _prefs!.getKeys();
    final cacheKeys = keys.where((k) => k.startsWith(_prefix)).toList();

    int expired = 0;
    int valid = 0;

    for (final key in cacheKeys) {
      final actualKey = key.substring(_prefix.length);
      if (_isExpired(actualKey)) {
        expired++;
      } else {
        valid++;
      }
    }

    return {
      'total': cacheKeys.length,
      'valid': valid,
      'expired': expired,
    };
  }

  /// Get approximate cache size in bytes
  static Future<int> getApproximateSize() async {
    _ensureInitialized();

    final keys = _prefs!.getKeys();
    final cacheKeys = keys.where((k) => k.startsWith(_prefix));

    int totalSize = 0;

    for (final key in cacheKeys) {
      final value = _prefs!.getString(key);
      if (value != null) {
        totalSize += key.length + value.length;
      }
    }

    return totalSize;
  }

  // Cache multiple items at once
  static Future<void> setMap(Map<String, dynamic> data, {Duration? duration}) async {
    for (final entry in data.entries) {
      await set(entry.key, entry.value, duration: duration);
    }
  }

  // Get multiple items at once
  static Map<String, dynamic> getMap(List<String> keys) {
    final result = <String, dynamic>{};

    for (final key in keys) {
      final value = get<dynamic>(key);
      if (value != null) {
        result[key] = value;
      }
    }

    return result;
  }

  // Check if cache entry is expired
  static bool _isExpired(String key) {
    final expiryStr = _prefs!.getString('$_timestampPrefix${key}_expiry');
    if (expiryStr == null) return false;

    try {
      final expiry = DateTime.parse(expiryStr);
      return DateTime.now().isAfter(expiry);
    } catch (e) {
      return false;
    }
  }

  // Encode value to JSON string
  static String _encode<T>(T value) {
    if (value is String) return value;
    if (value is num) return value.toString();
    if (value is bool) return value.toString();
    if (value is Map || value is List) {
      return jsonEncode(value);
    }
    throw ArgumentError('Unsupported type: ${T.runtimeType}');
  }

  // Decode JSON string to value
  static T? _decode<T>(String jsonString) {
    if (T == String) return jsonString as T;
    if (T == int) return int.tryParse(jsonString) as T?;
    if (T == double) return double.tryParse(jsonString) as T?;
    if (T == bool) {
      if (jsonString.toLowerCase() == 'true') return true as T;
      if (jsonString.toLowerCase() == 'false') return false as T;
      return null;
    }

    // Try to decode as JSON for Map and List
    try {
      final decoded = jsonDecode(jsonString);
      return decoded as T?;
    } catch (e) {
      return null;
    }
  }

  static void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'OfflineCache not initialized. Call OfflineCache.init() first.',
      );
    }
  }
}

/// Typed cache keys for better type safety
class CacheKeys {
  // User data
  static const String userProfile = 'user_profile';
  static const String userVehicles = 'user_vehicles';
  static const String userRoutes = 'user_routes';

  // Ride data
  static const String activeRide = 'active_ride';
  static const String rideHistory = 'ride_history';
  static const String driverRoutes = 'driver_routes';

  // Location data
  static const String recentLocations = 'recent_locations';
  static const String homeLocation = 'home_location';
  static const String workLocation = 'work_location';

  // App data
  static const String fareRules = 'fare_rules';
  static const String serviceArea = 'service_area';
  static const String appConfig = 'app_config';

  // Ratings
  static const String userRatings = 'user_ratings_';
}

/// Extension for common cache operations
class CacheHelpers {
  /// Cache user profile
  static Future<void> setUserProfile(Map<String, dynamic> profile) async {
    await OfflineCache.set(CacheKeys.userProfile, profile, duration: OfflineCache.longCacheDuration);
  }

  /// Get cached user profile
  static Map<String, dynamic>? getUserProfile() {
    return OfflineCache.get<Map<String, dynamic>>(CacheKeys.userProfile);
  }

  /// Cache active ride
  static Future<void> setActiveRide(Map<String, dynamic> ride) async {
    await OfflineCache.set(CacheKeys.activeRide, ride, duration: OfflineCache.shortCacheDuration);
  }

  /// Get cached active ride
  static Map<String, dynamic>? getActiveRide() {
    return OfflineCache.get<Map<String, dynamic>>(CacheKeys.activeRide);
  }

  /// Cache recent locations
  static Future<void> setRecentLocations(List<Map<String, dynamic>> locations) async {
    await OfflineCache.set(CacheKeys.recentLocations, locations, duration: OfflineCache.longCacheDuration);
  }

  /// Get cached recent locations
  static List<Map<String, dynamic>>? getRecentLocations() {
    return OfflineCache.get<List<Map<String, dynamic>>>(CacheKeys.recentLocations);
  }

  /// Add location to recent locations
  static Future<void> addRecentLocation(Map<String, dynamic> location) async {
    final current = getRecentLocations() ?? [];
    final updated = [location, ...current.where((l) => l['id'] != location['id'])].take(10).toList();
    await setRecentLocations(updated);
  }
}
