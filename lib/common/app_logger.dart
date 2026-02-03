import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// A centralized logging service for the application.
///
/// Usage:
/// ```dart
/// AppLogger.i('User logged in');
/// AppLogger.e('API request failed', error, stackTrace);
/// AppLogger.w('Deprecated API called');
/// ```
///
/// In debug mode, logs are printed with colors and formatting.
/// In release mode, only warnings and errors are logged.
final class AppLogger {
  AppLogger._();

  static Logger? _logger;
  static bool _initialized = false;

  /// Initialize the logger with appropriate settings for the environment.
  /// Call this once at app startup, typically in main().
  static void initialize({bool verbose = false}) {
    if (_initialized) return;

    _logger = Logger(
      level: kDebugMode ? Level.all : Level.warning,
      printer: PrettyPrinter(
        methodCount: kDebugMode ? 2 : 0,
        errorMethodCount: kDebugMode ? 8 : 0,
        lineLength: 120,
        colors: kDebugMode,
        printEmojis: kDebugMode,
        dateTimeFormat: kDebugMode ? DateTimeFormat.onlyTimeAndSinceStart : DateTimeFormat.none,
        noBoxingByDefault: false,
      ),
      filter: kReleaseMode ? ProductionFilter() : DevelopmentFilter(),
      output: _ConsoleOutput(),
    );

    _initialized = true;
  }

  /// Log an informational message
  static void i(
    dynamic message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    _ensureInitialized();
    _logger!.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log a debug message
  static void d(
    dynamic message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    _ensureInitialized();
    _logger!.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log a warning message
  static void w(
    dynamic message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    _ensureInitialized();
    _logger!.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log an error message
  static void e(
    dynamic message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    _ensureInitialized();
    _logger!.e(message, error: error, stackTrace: stackTrace);
  }

  /// Log a verbose trace message
  static void t(
    dynamic message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    _ensureInitialized();
    _logger!.t(message, error: error, stackTrace: stackTrace);
  }

  /// Log a fatal error
  static void fatal(
    dynamic message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    _ensureInitialized();
    _logger!.f(message, error: error, stackTrace: stackTrace);
  }

  static void _ensureInitialized() {
    if (!_initialized) {
      initialize();
    }
  }
}

/// Filter for development mode - logs everything
class DevelopmentFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    return true;
  }
}

/// Filter for production mode - only warnings and errors
class ProductionFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    return event.level.index >= Level.warning.index;
  }
}

/// Output to console
class _ConsoleOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      // ignore: avoid_print - this is the logger output
      print(line);
    }
  }
}
