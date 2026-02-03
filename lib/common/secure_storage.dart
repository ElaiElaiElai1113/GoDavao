import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A secure storage service for sensitive data like auth tokens.
///
/// Uses:
/// - [FlutterSecureStorage] on mobile (encrypted)
/// - [SharedPreferences] on web (fallback, not encrypted)
///
/// Usage:
/// ```dart
/// await SecureStorage.init();
/// await SecureStorage.setToken('access_token', 'jwt_token_here');
/// final token = await SecureStorage.getToken('access_token');
/// ```
final class SecureStorage {
  SecureStorage._();

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static SharedPreferences? _prefs;
  static bool _initialized = false;

  /// Keys for stored values
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userIdKey = 'user_id';
  static const String userEmailKey = 'user_email';
  static const String userRoleKey = 'user_role';
  static const String biometricEnabledKey = 'biometric_enabled';

  /// Initialize the secure storage. Call once at app startup.
  static Future<void> init() async {
    if (_initialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    } catch (e) {
      debugPrint('Failed to initialize SecureStorage: $e');
      rethrow;
    }
  }

  /// Store an access token securely
  static Future<void> setAccessToken(String token) async {
    _ensureInitialized();
    try {
      await _secureStorage.write(key: accessTokenKey, value: token);
    } catch (e) {
      debugPrint('Failed to store access token: $e');
      rethrow;
    }
  }

  /// Get the stored access token
  static Future<String?> getAccessToken() async {
    _ensureInitialized();
    try {
      return await _secureStorage.read(key: accessTokenKey);
    } catch (e) {
      debugPrint('Failed to read access token: $e');
      return null;
    }
  }

  /// Store a refresh token securely
  static Future<void> setRefreshToken(String token) async {
    _ensureInitialized();
    try {
      await _secureStorage.write(key: refreshTokenKey, value: token);
    } catch (e) {
      debugPrint('Failed to store refresh token: $e');
      rethrow;
    }
  }

  /// Get the stored refresh token
  static Future<String?> getRefreshToken() async {
    _ensureInitialized();
    try {
      return await _secureStorage.read(key: refreshTokenKey);
    } catch (e) {
      debugPrint('Failed to read refresh token: $e');
      return null;
    }
  }

  /// Store user ID
  static Future<void> setUserId(String userId) async {
    _ensureInitialized();
    try {
      await _secureStorage.write(key: userIdKey, value: userId);
    } catch (e) {
      debugPrint('Failed to store user ID: $e');
    }
  }

  /// Get the stored user ID
  static Future<String?> getUserId() async {
    _ensureInitialized();
    try {
      return await _secureStorage.read(key: userIdKey);
    } catch (e) {
      debugPrint('Failed to read user ID: $e');
      return null;
    }
  }

  /// Store user email
  static Future<void> setUserEmail(String email) async {
    _ensureInitialized();
    try {
      await _secureStorage.write(key: userEmailKey, value: email);
    } catch (e) {
      debugPrint('Failed to store user email: $e');
    }
  }

  /// Get the stored user email
  static Future<String?> getUserEmail() async {
    _ensureInitialized();
    try {
      return await _secureStorage.read(key: userEmailKey);
    } catch (e) {
      debugPrint('Failed to read user email: $e');
      return null;
    }
  }

  /// Store user role
  static Future<void> setUserRole(String role) async {
    _ensureInitialized();
    try {
      await _secureStorage.write(key: userRoleKey, value: role);
    } catch (e) {
      debugPrint('Failed to store user role: $e');
    }
  }

  /// Get the stored user role
  static Future<String?> getUserRole() async {
    _ensureInitialized();
    try {
      return await _secureStorage.read(key: userRoleKey);
    } catch (e) {
      debugPrint('Failed to read user role: $e');
      return null;
    }
  }

  /// Set biometric authentication preference
  static Future<void> setBiometricEnabled(bool enabled) async {
    _ensureInitialized();
    try {
      await _secureStorage.write(
        key: biometricEnabledKey,
        value: enabled.toString(),
      );
    } catch (e) {
      debugPrint('Failed to store biometric preference: $e');
    }
  }

  /// Get biometric authentication preference
  static Future<bool> getBiometricEnabled() async {
    _ensureInitialized();
    try {
      final value = await _secureStorage.read(key: biometricEnabledKey);
      return value == 'true';
    } catch (e) {
      debugPrint('Failed to read biometric preference: $e');
      return false;
    }
  }

  /// Store a generic key-value pair securely
  static Future<void> set(String key, String value) async {
    _ensureInitialized();
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (e) {
      debugPrint('Failed to store $key: $e');
      rethrow;
    }
  }

  /// Get a stored value by key
  static Future<String?> get(String key) async {
    _ensureInitialized();
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      debugPrint('Failed to read $key: $e');
      return null;
    }
  }

  /// Remove a stored value by key
  static Future<void> remove(String key) async {
    _ensureInitialized();
    try {
      await _secureStorage.delete(key: key);
    } catch (e) {
      debugPrint('Failed to remove $key: $e');
    }
  }

  /// Clear all stored data (useful for logout)
  static Future<void> clearAll() async {
    _ensureInitialized();
    try {
      await _secureStorage.deleteAll();
      await _prefs?.clear();
    } catch (e) {
      debugPrint('Failed to clear storage: $e');
      rethrow;
    }
  }

  /// Check if a user is logged in (has valid tokens)
  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// Get all stored keys (for debugging)
  static Future<Set<String>> getAllKeys() async {
    _ensureInitialized();
    try {
      return await _secureStorage.readAll().then((map) => map.keys.toSet());
    } catch (e) {
      debugPrint('Failed to read all keys: $e');
      return {};
    }
  }

  static void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'SecureStorage not initialized. Call SecureStorage.init() first.',
      );
    }
  }

  // Preferences for non-sensitive data (using SharedPreferences)
  static Future<void> setPref(String key, bool value) async {
    _ensureInitialized();
    await _prefs?.setBool(key, value);
  }

  static Future<bool?> getPref(String key) async {
    _ensureInitialized();
    return _prefs?.getBool(key);
  }

  static Future<void> setPrefString(String key, String value) async {
    _ensureInitialized();
    await _prefs?.setString(key, value);
  }

  static Future<String?> getPrefString(String key) async {
    _ensureInitialized();
    return _prefs?.getString(key);
  }

  static Future<void> setPrefInt(String key, int value) async {
    _ensureInitialized();
    await _prefs?.setInt(key, value);
  }

  static Future<int?> getPrefInt(String key) async {
    _ensureInitialized();
    return _prefs?.getInt(key);
  }

  static Future<void> removePref(String key) async {
    _ensureInitialized();
    await _prefs?.remove(key);
  }
}

/// Token storage model for easy access
class AuthTokens {
  final String accessToken;
  final String? refreshToken;

  const AuthTokens({
    required this.accessToken,
    this.refreshToken,
  });

  /// Save tokens to secure storage
  Future<void> save() async {
    await SecureStorage.setAccessToken(accessToken);
    if (refreshToken != null) {
      await SecureStorage.setRefreshToken(refreshToken!);
    }
  }

  /// Load tokens from secure storage
  static Future<AuthTokens?> load() async {
    final accessToken = await SecureStorage.getAccessToken();
    final refreshToken = await SecureStorage.getRefreshToken();

    if (accessToken == null) return null;

    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  /// Clear tokens from secure storage
  static Future<void> clear() async {
    await SecureStorage.remove(SecureStorage.accessTokenKey);
    await SecureStorage.remove(SecureStorage.refreshTokenKey);
  }
}
