import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:godavao/common/app_logger.dart';

/// Centralized error handling for the application.
///
/// Handles:
/// - Uncaught exceptions
/// - Async errors not caught by try-catch
/// - Flutter framework errors
/// - User-friendly error messages
final class ErrorHandler {
  ErrorHandler._();

  static const _defaultErrorMessage = 'An unexpected error occurred. Please try again.';

  static bool _initialized = false;

  /// Initialize global error handlers. Call once in main().
  static void initialize() {
    if (_initialized) return;

    // Catch all unhandled errors in the Flutter framework
    FlutterError.onError = _handleFlutterError;

    // Catch all unhandled async errors
    PlatformDispatcher.instance.onError = _handlePlatformError;

    _initialized = true;
  }

  /// Handle Flutter framework errors
  static void _handleFlutterError(FlutterErrorDetails details) {
    // Log the error
    AppLogger.e(
      'Flutter Error',
      details.exception,
      details.stack,
    );

    // In debug mode, show the red screen of death
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(details);
    }

    // In release mode, you might want to send this to a crash reporting service
    if (kReleaseMode) {
      // TODO: Send to crash reporting service (Sentry, Firebase Crashlytics, etc.)
    }
  }

  /// Handle platform errors (async errors not caught by try-catch)
  static bool _handlePlatformError(Object error, StackTrace stack) {
    AppLogger.e(
      'Uncaught Async Error',
      error,
      stack,
    );

    // In release mode, send to crash reporting
    if (kReleaseMode) {
      // TODO: Send to crash reporting service
    }

    // Return true to indicate the error was handled
    return true;
  }

  /// Handle a specific error and return a user-friendly message
  static String getUserMessage(Object? error) {
    if (error == null) return _defaultErrorMessage;

    // Custom error types
    if (error is AppException) {
      return error.userMessage;
    }

    // Network errors
    if (error.toString().contains('SocketException')) {
      return 'No internet connection. Please check your network.';
    }
    if (error.toString().contains('TimeoutException')) {
      return 'Request timed out. Please try again.';
    }
    if (error.toString().contains('HttpException')) {
      return 'Server error. Please try again later.';
    }

    // Auth errors
    if (error.toString().contains('Unauthorized') ||
        error.toString().contains('401')) {
      return 'Session expired. Please log in again.';
    }
    if (error.toString().contains('Forbidden') ||
        error.toString().contains('403')) {
      return 'You don\'t have permission to perform this action.';
    }

    // Generic fallback
    return _defaultErrorMessage;
  }

  /// Show an error dialog to the user
  static Future<void> showErrorDialog(
    BuildContext context,
    Object? error, {
    String? title,
    VoidCallback? onRetry,
  }) {
    return showDialog(
      context: context,
      builder: (context) => ErrorDialog(
        title: title ?? 'Error',
        message: getUserMessage(error),
        onRetry: onRetry,
      ),
    );
  }

  /// Show a snackbar error message
  static void showSnackBar(
    BuildContext context,
    Object? error, {
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(getUserMessage(error)),
        backgroundColor: Colors.red,
        action: action,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Run a function with error handling
  static Future<T?> guard<T>(
    Future<T> Function() fn, {
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    try {
      return await fn();
    } catch (error, stack) {
      AppLogger.e('Error in guarded function', error, stack);
      onError?.call(error, stack);
      return null;
    }
  }

  /// Run a function and show error dialog on failure
  static Future<T?> guardWithDialog<T>(
    BuildContext context,
    Future<T> Function() fn, {
    String? errorMessage,
  }) async {
    try {
      return await fn();
    } catch (error, stack) {
      AppLogger.e('Error in function with dialog', error, stack);
      if (context.mounted) {
        await showErrorDialog(
          context,
          error,
          title: 'Error',
        );
      }
      return null;
    }
  }
}

/// Base class for all application exceptions
abstract class AppException implements Exception {
  final String message;
  final String userMessage;
  final Object? originalError;
  final StackTrace? stackTrace;

  const AppException({
    required this.message,
    required this.userMessage,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => message;
}

/// Network-related exceptions
class NetworkException extends AppException {
  const NetworkException({
    String message = 'Network error occurred',
    String userMessage = 'Network error. Please check your connection.',
    Object? originalError,
    StackTrace? stackTrace,
  }) : super(
          message: message,
          userMessage: userMessage,
          originalError: originalError,
          stackTrace: stackTrace,
        );

  factory NetworkException.timeout({Object? error, StackTrace? stack}) {
    return NetworkException(
      message: 'Request timeout',
      userMessage: 'Request timed out. Please try again.',
      originalError: error,
      stackTrace: stack,
    );
  }

  factory NetworkException.noInternet({Object? error, StackTrace? stack}) {
    return NetworkException(
      message: 'No internet connection',
      userMessage: 'No internet connection. Please check your network.',
      originalError: error,
      stackTrace: stack,
    );
  }

  factory NetworkException.serverError({Object? error, StackTrace? stack}) {
    return NetworkException(
      message: 'Server error',
      userMessage: 'Server error. Please try again later.',
      originalError: error,
      stackTrace: stack,
    );
  }
}

/// Authentication-related exceptions
class AuthException extends AppException {
  const AuthException({
    String message = 'Authentication failed',
    String userMessage = 'Authentication failed. Please log in again.',
    Object? originalError,
    StackTrace? stackTrace,
  }) : super(
          message: message,
          userMessage: userMessage,
          originalError: originalError,
          stackTrace: stackTrace,
        );

  factory AuthException.sessionExpired({Object? error, StackTrace? stack}) {
    return AuthException(
      message: 'Session expired',
      userMessage: 'Your session has expired. Please log in again.',
      originalError: error,
      stackTrace: stack,
    );
  }

  factory AuthException.invalidCredentials({Object? error, StackTrace? stack}) {
    return AuthException(
      message: 'Invalid credentials',
      userMessage: 'Invalid email or password. Please try again.',
      originalError: error,
      stackTrace: stack,
    );
  }

  factory AuthException.unauthorized({Object? error, StackTrace? stack}) {
    return AuthException(
      message: 'Unauthorized access',
      userMessage: 'You need to log in to perform this action.',
      originalError: error,
      stackTrace: stack,
    );
  }
}

/// Validation-related exceptions
class ValidationException extends AppException {
  final Map<String, String>? fieldErrors;

  const ValidationException({
    String message = 'Validation failed',
    String userMessage = 'Please check your input and try again.',
    this.fieldErrors,
    Object? originalError,
    StackTrace? stackTrace,
  }) : super(
          message: message,
          userMessage: userMessage,
          originalError: originalError,
          stackTrace: stackTrace,
        );
}

/// Database-related exceptions
class DatabaseException extends AppException {
  const DatabaseException({
    String message = 'Database error',
    String userMessage = 'A data error occurred. Please try again.',
    Object? originalError,
    StackTrace? stackTrace,
  }) : super(
          message: message,
          userMessage: userMessage,
          originalError: originalError,
          stackTrace: stackTrace,
        );
}

/// Error dialog widget
class ErrorDialog extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const ErrorDialog({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onRetry!();
            },
            child: const Text('Retry'),
          ),
      ],
    );
  }
}

/// Extension to catch errors on Futures
extension ErrorCatcher<T> on Future<T> {
  /// Catch errors and return null on failure
  Future<T?> catchToNull() async {
    try {
      return await this;
    } catch (error, stack) {
      AppLogger.e('Caught error', error, stack);
      return null;
    }
  }

  /// Catch errors and return a default value on failure
  Future<T> catchTo(T defaultValue) async {
    try {
      return await this;
    } catch (error, stack) {
      AppLogger.e('Caught error', error, stack);
      return defaultValue;
    }
  }
}

/// Extension to catch errors on Streams
extension StreamErrorCatcher<T> on Stream<T> {
  /// Catch errors and return a Stream that doesn't emit errors
  Stream<T> catchErrors() {
    return handleError(
      (Object error, StackTrace stack) {
        AppLogger.e('Stream error', error, stack);
      },
    );
  }
}
