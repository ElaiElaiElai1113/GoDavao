import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Application configuration loaded from environment variables.
///
/// Environment files (.env) should be placed in the project root.
/// Different environments can use different .env files:
/// - .env (default/local)
/// - .env.staging (staging environment)
/// - .env.production (production environment)
final class AppConfig {
  AppConfig._();

  static bool _initialized = false;

  // Supabase Configuration
  static String get supabaseUrl {
    _ensureInitialized();
    return dotenv.get('SUPABASE_URL', fallback: '');
  }

  static String get supabaseAnonKey {
    _ensureInitialized();
    return dotenv.get('SUPABASE_ANON_KEY', fallback: '');
  }

  // OSRM Configuration
  static String get osrmUrl {
    _ensureInitialized();
    return dotenv.get('OSRM_URL', fallback: 'http://router.project-osrm.org');
  }

  // Mapbox Configuration (optional, for additional features)
  static String? get mapboxAccessToken {
    _ensureInitialized();
    final token = dotenv.maybeGet('MAPBOX_ACCESS_TOKEN');
    return token?.isEmpty ?? true ? null : token;
  }

  // Environment Configuration
  static AppEnvironment get environment {
    _ensureInitialized();
    final env = dotenv.get('ENVIRONMENT', fallback: 'development');
    return AppEnvironment.values.firstWhere(
      (e) => e.name == env,
      orElse: () => AppEnvironment.development,
    );
  }

  static bool get isDevelopment => environment == AppEnvironment.development;
  static bool get isStaging => environment == AppEnvironment.staging;
  static bool get isProduction => environment == AppEnvironment.production;

  // API Configuration
  static String get apiBaseUrl {
    _ensureInitialized();
    return dotenv.get('API_BASE_URL', fallback: supabaseUrl);
  }

  static Duration get apiTimeout {
    final seconds = int.tryParse(dotenv.get('API_TIMEOUT', fallback: '30')) ?? 30;
    return Duration(seconds: seconds);
  }

  // Feature Flags
  static bool get enableDebugTools {
    _ensureInitialized();
    final flag = dotenv.get('ENABLE_DEBUG_TOOLS', fallback: 'false');
    return flag == 'true' || kDebugMode;
  }

  static bool get enableAnalytics {
    _ensureInitialized();
    final flag = dotenv.get('ENABLE_ANALYTICS', fallback: 'true');
    return flag == 'true' && kReleaseMode;
  }

  static bool get enableCrashReporting {
    _ensureInitialized();
    final flag = dotenv.get('ENABLE_CRASH_REPORTING', fallback: 'true');
    return flag == 'true' && kReleaseMode;
  }

  // Logging Configuration
  static LogLevel get logLevel {
    _ensureInitialized();
    final level = dotenv.get('LOG_LEVEL', fallback: 'info');
    return LogLevel.values.firstWhere(
      (l) => l.name == level,
      orElse: () => LogLevel.info,
    );
  }

  // Fare Configuration (can be overridden by env)
  static double get baseFare {
    _ensureInitialized();
    return double.tryParse(dotenv.get('BASE_FARE', fallback: '25.0')) ?? 25.0;
  }

  static double get perKmRate {
    _ensureInitialized();
    return double.tryParse(dotenv.get('PER_KM_RATE', fallback: '14.0')) ?? 14.0;
  }

  static double get perMinRate {
    _ensureInitialized();
    return double.tryParse(dotenv.get('PER_MIN_RATE', fallback: '0.8')) ?? 0.8;
  }

  // Service Area Configuration (Davao City bounds)
  static LatLngBounds get serviceAreaBounds {
    _ensureInitialized();
    return LatLngBounds(
      south: double.tryParse(dotenv.get('BOUND_SOUTH', fallback: '6.9')) ?? 6.9,
      west: double.tryParse(dotenv.get('BOUND_WEST', fallback: '125.3')) ?? 125.3,
      north: double.tryParse(dotenv.get('BOUND_NORTH', fallback: '7.2')) ?? 7.2,
      east: double.tryParse(dotenv.get('BOUND_EAST', fallback: '125.7')) ?? 125.7,
    );
  }

  // App Information
  static String get appName => 'GoDavao';
  static String get appVersion => '1.0.0';
  static String get buildNumber => '1';

  /// Initialize the app configuration.
  /// [envFile] can be used to load a specific environment file.
  static Future<void> init({String envFile = '.env'}) async {
    if (_initialized) return;

    try {
      await dotenv.load(fileName: envFile);
      _initialized = true;

      if (kDebugMode) {
        // ignore: avoid_print - debug info
        print('AppConfig loaded: ${environment.name} mode');
      }
    } catch (e) {
      // Use default values if .env file is missing
      if (kDebugMode) {
        // ignore: avoid_print - debug info
        print('Warning: $envFile file not found, using defaults');
      }
      _initialized = true;
    }
  }

  /// Load a specific environment configuration
  static Future<void> loadEnvironment(String env) async {
    final envFile = '.env.$env';
    await init(envFile: envFile);
  }

  static void _ensureInitialized() {
    if (!_initialized) {
      debugPrint(
        'Warning: AppConfig not initialized. Call AppConfig.init() first.',
      );
    }
  }

  /// Get all configuration values as a map (for debugging)
  static Map<String, String> getAll() {
    _ensureInitialized();
    return dotenv.env;
  }
}

/// Application environment
enum AppEnvironment {
  development,
  staging,
  production,
}

/// Log level enum
enum LogLevel {
  trace,
  debug,
  info,
  warning,
  error,
  fatal,
}

/// Service area bounds
class LatLngBounds {
  final double south;
  final double west;
  final double north;
  final double east;

  const LatLngBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  /// Check if a point is within the bounds
  bool contains(double lat, double lng) {
    return lat >= south && lat <= north && lng >= west && lng <= east;
  }

  @override
  String toString() =>
      'LatLngBounds(south: $south, west: $west, north: $north, east: $east)';
}

/// Extension to get display name for AppEnvironment
extension AppEnvironmentExtension on AppEnvironment {
  String get displayName {
    switch (this) {
      case AppEnvironment.development:
        return 'Development';
      case AppEnvironment.staging:
        return 'Staging';
      case AppEnvironment.production:
        return 'Production';
    }
  }

  String get shortName {
    switch (this) {
      case AppEnvironment.development:
        return 'DEV';
      case AppEnvironment.staging:
        return 'STG';
      case AppEnvironment.production:
        return 'PRD';
    }
  }
}
