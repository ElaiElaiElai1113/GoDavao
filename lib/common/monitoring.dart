import 'package:flutter/foundation.dart';

import 'package:godavao/common/app_logger.dart';
import 'package:godavao/common/app_config.dart';

/// Monitoring and analytics service.
///
/// Integrates with crash reporting and analytics platforms.
/// For production use, integrate with:
/// - Sentry (crash reporting)
/// - Firebase Analytics (analytics)
/// - Mixpanel/Amplitude (event tracking)
final class MonitoringService {
  MonitoringService._();

  static bool _initialized = false;
  static bool _enabled = false;

  /// Initialize the monitoring service
  static void init() {
    if (_initialized) return;

    _enabled = AppConfig.enableCrashReporting || AppConfig.enableAnalytics;

    if (_enabled) {
      if (kDebugMode) {
        // ignore: avoid_print - debug info
        print('MonitoringService initialized (enabled: $_enabled)');
      }

      if (AppConfig.enableCrashReporting) {
        _initCrashReporting();
      }

      if (AppConfig.enableAnalytics) {
        _initAnalytics();
      }
    }

    _initialized = true;
  }

  /// Initialize crash reporting (Sentry, Firebase Crashlytics, etc.)
  static void _initCrashReporting() {
    // TODO: Integrate Sentry or Firebase Crashlytics
    //
    // Example with Sentry:
    // await SentryFlutter.init(
    //   (options) => {
    //     options.dsn = 'YOUR_SENTRY_DSN',
    //     options.tracesSampleRate = AppConfig.isProduction ? 0.2 : 1.0,
    //     options.environment = AppConfig.environment.name,
    //   },
    //   appRunner: () => runApp(MyApp()),
    // );

    if (kDebugMode) {
      // ignore: avoid_print - debug info
      print('Crash reporting initialized');
    }
  }

  /// Initialize analytics (Firebase Analytics, Mixpanel, etc.)
  static void _initAnalytics() {
    // TODO: Integrate Firebase Analytics or other analytics
    //
    // Example with Firebase Analytics:
    // await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
    //
    // Example with Mixpanel:
    // await Mixpanel.init('YOUR_MIXPANEL_TOKEN');

    if (kDebugMode) {
      // ignore: avoid_print - debug info
      print('Analytics initialized');
    }
  }

  /// Log a custom event
  static void logEvent(
    String name, {
    Map<String, dynamic>? parameters,
  }) {
    if (!_enabled) return;

    try {
      AppLogger.d('Event: $name', parameters ?? '');

      // TODO: Send to analytics platform
      // FirebaseAnalytics.instance.logEvent(
      //   name: name,
      //   parameters: parameters,
      // );
    } catch (e) {
      AppLogger.e('Failed to log event: $name', e);
    }
  }

  /// Set user ID for analytics/crash reporting
  static void setUserId(String userId) {
    if (!_enabled) return;

    try {
      AppLogger.d('Set user ID: $userId');

      // TODO: Set user ID in analytics/crash reporting
      // Sentry.setUser(id: userId);
      // FirebaseAnalytics.instance.setUserId(userId);
    } catch (e) {
      AppLogger.e('Failed to set user ID', e);
    }
  }

  /// Set user properties for analytics
  static void setUserProperty(String name, String? value) {
    if (!_enabled) return;

    try {
      AppLogger.d('Set user property: $name = $value');

      // TODO: Set user property in analytics
      // FirebaseAnalytics.instance.setUserProperty(name: name, value: value);
    } catch (e) {
      AppLogger.e('Failed to set user property: $name', e);
    }
  }

  /// Log an error to crash reporting
  static void logError(
    Object error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    bool fatal = false,
  }) {
    if (!_enabled) return;

    try {
      AppLogger.e(
        'Error logged: ${error.toString()}',
        error,
        stackTrace,
      );

      // TODO: Send to crash reporting
      // Sentry.captureException(
      //   error,
      //   stackTrace: stackTrace,
      //   hint: Hint.withMap(context),
      //   level: fatal ? Level.fatal : Level.error,
      // );
    } catch (e) {
      AppLogger.e('Failed to log error', e);
    }
  }

  /// Log a message/breadcrumb for crash context
  static void logBreadcrumb(
    String message, {
    Map<String, dynamic>? data,
  }) {
    if (!_enabled) return;

    try {
      AppLogger.d('Breadcrumb: $message', data ?? '');

      // TODO: Add breadcrumb to crash reporting
      // Sentry.addBreadcrumb(
      //   Breadcrumb(
      //     message: message,
      //     data: data,
      //     category: 'custom',
      //   ),
      // );
    } catch (e) {
      AppLogger.e('Failed to add breadcrumb', e);
    }
  }

  /// Track screen view
  static void trackScreen(String screenName) {
    if (!_enabled) return;

    try {
      logEvent('screen_view', parameters: {'screen_name': screenName});

      // TODO: Track screen view in analytics
      // FirebaseAnalytics.instance.logScreenView(screenName: screenName);
    } catch (e) {
      AppLogger.e('Failed to track screen: $screenName', e);
    }
  }

  /// Track ride-related events
  static void trackRideEvent(
    String action, {
    required String rideId,
    Map<String, dynamic>? additionalParams,
  }) {
    logEvent(
      'ride_$action',
      parameters: {
        'ride_id': rideId,
        ...?additionalParams,
      },
    );
  }

  /// Track payment events
  static void trackPaymentEvent({
    required String paymentId,
    required double amount,
    required String status,
  }) {
    logEvent(
      'payment_$status',
      parameters: {
        'payment_id': paymentId,
        'amount': amount,
        'status': status,
      },
    );
  }

  /// Track user engagement
  static void trackEngagement(String action) {
    logEvent(
      'engagement',
      parameters: {'action': action},
    );
  }

  /// Clear user data (logout)
  static void clearUser() {
    if (!_enabled) return;

    try {
      AppLogger.d('Cleared user data');

      // TODO: Clear user data from analytics/crash reporting
      // Sentry.setUser(null);
      // FirebaseAnalytics.instance.resetAnalyticsData();
    } catch (e) {
      AppLogger.e('Failed to clear user data', e);
    }
  }

  /// Get monitoring enabled status
  static bool get isEnabled => _enabled;

  /// Check if crash reporting is enabled
  static bool get crashReportingEnabled => AppConfig.enableCrashReporting && _enabled;

  /// Check if analytics is enabled
  static bool get analyticsEnabled => AppConfig.enableAnalytics && _enabled;
}

/// Predefined event names for consistent tracking
class MonitoringEvents {
  // Auth events
  static const String login = 'login';
  static const String logout = 'logout';
  static const String signup = 'signup';
  static const String passwordReset = 'password_reset';

  // Ride events
  static const String rideRequested = 'ride_requested';
  static const String rideAccepted = 'ride_accepted';
  static const String rideDeclined = 'ride_declined';
  static const String rideStarted = 'ride_started';
  static const String rideCompleted = 'ride_completed';
  static const String rideCancelled = 'ride_cancelled';

  // Payment events
  static const String paymentInitiated = 'payment_initiated';
  static const String paymentCompleted = 'payment_completed';
  static const String paymentFailed = 'payment_failed';

  // UI events
  static const String buttonClicked = 'button_clicked';
  static const String formSubmitted = 'form_submitted';
  static const String pageViewed = 'page_viewed';
  static const String modalOpened = 'modal_opened';
  static const String modalClosed = 'modal_closed';

  // Error events
  static const String apiError = 'api_error';
  static const String validationError = 'validation_error';
  static const String networkError = 'network_error';
}

/// Predefined user properties
class MonitoringUserProperties {
  static const String userRole = 'user_role';
  static const String isDriver = 'is_driver';
  static const String isPassenger = 'is_passenger';
  static const String isVerified = 'is_verified';
  static const String memberSince = 'member_since';
  static const String totalRides = 'total_rides';
  static const String totalSpent = 'total_spent';
}
