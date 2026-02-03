import 'package:latlong2/latlong.dart';

/// Common validation functions for GoDavao inputs.
///
/// All validators return a [ValidationResult] containing either
/// success or an error message.
sealed class ValidationResult {
  const ValidationResult();

  bool get isValid => this is ValidationSuccess;
  bool get isInvalid => this is ValidationFailure;

  String? get errorMessage => when(
        success: () => null,
        failure: (msg) => msg,
      );

  T when<T>({
    required T Function() success,
    required T Function(String message) failure,
  }) {
    return switch (this) {
      ValidationSuccess() => success(),
      ValidationFailure(:final message) => failure(message),
    };
  }
}

final class ValidationSuccess extends ValidationResult {
  const ValidationSuccess();
}

final class ValidationFailure extends ValidationResult {
  final String message;
  const ValidationFailure(this.message);
}

/// Centralized validator for all input types.
class Validators {
  Validators._();

  // Validation constants
  static const int minNameLength = 2;
  static const int maxNameLength = 50;
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 128;
  static const int minAddressLength = 5;
  static const int maxAddressLength = 200;
  static const int minPlateNumberLength = 4;
  static const int maxPlateNumberLength = 10;

  // Davao City coordinate bounds (approximately)
  static const double minLat = 6.9; // South of Davao
  static const double maxLat = 7.2; // North of Davao
  static const double minLng = 125.3; // West of Davao
  static const double maxLng = 125.7; // East of Davao

  /// Validates a person's name
  static ValidationResult name(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const ValidationFailure('Name is required');
    }
    final trimmed = value.trim();
    if (trimmed.length < minNameLength) {
      return ValidationFailure('Name must be at least $minNameLength characters');
    }
    if (trimmed.length > maxNameLength) {
      return ValidationFailure('Name must not exceed $maxNameLength characters');
    }
    // Check for valid characters (letters, spaces, hyphens, apostrophes)
    if (!RegExp(r"^[\p{L}\s'-]+$", unicode: true).hasMatch(trimmed)) {
      return const ValidationFailure('Name contains invalid characters');
    }
    return const ValidationSuccess();
  }

  /// Validates an email address
  static ValidationResult email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const ValidationFailure('Email is required');
    }
    final trimmed = value.trim().toLowerCase();
    // Basic email regex
    final emailRegex = RegExp(
      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
    );
    if (!emailRegex.hasMatch(trimmed)) {
      return const ValidationFailure('Please enter a valid email address');
    }
    return const ValidationSuccess();
  }

  /// Validates a phone number (Philippines format)
  static ValidationResult phoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const ValidationFailure('Phone number is required');
    }
    final trimmed = value.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    // Philippine mobile numbers: 09XXXXXXXXX or +639XXXXXXXXX
    final phoneRegex = RegExp(r'^(0|\+63)?9\d{9}$');
    if (!phoneRegex.hasMatch(trimmed)) {
      return const ValidationFailure('Please enter a valid Philippine mobile number');
    }
    return const ValidationSuccess();
  }

  /// Validates a password
  static ValidationResult password(String? value) {
    if (value == null || value.isEmpty) {
      return const ValidationFailure('Password is required');
    }
    if (value.length < minPasswordLength) {
      return ValidationFailure('Password must be at least $minPasswordLength characters');
    }
    if (value.length > maxPasswordLength) {
      return ValidationFailure('Password must not exceed $maxPasswordLength characters');
    }
    // Check for at least one letter and one number
    if (!RegExp(r'^(?=.*[A-Za-z])(?=.*\d)').hasMatch(value)) {
      return const ValidationFailure('Password must contain both letters and numbers');
    }
    return const ValidationSuccess();
  }

  /// Validates an address string
  static ValidationResult address(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const ValidationFailure('Address is required');
    }
    final trimmed = value.trim();
    if (trimmed.length < minAddressLength) {
      return ValidationFailure('Address must be at least $minAddressLength characters');
    }
    if (trimmed.length > maxAddressLength) {
      return ValidationFailure('Address must not exceed $maxAddressLength characters');
    }
    return const ValidationSuccess();
  }

  /// Validates a vehicle plate number (Philippines format)
  static ValidationResult plateNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const ValidationFailure('Plate number is required');
    }
    final trimmed = value.trim().toUpperCase();
    if (trimmed.length < minPlateNumberLength || trimmed.length > maxPlateNumberLength) {
      return ValidationFailure(
        'Plate number must be between $minPlateNumberLength and $maxPlateNumberLength characters',
      );
    }
    // Philippine plate format: ABC 123 or ABC 1234
    final plateRegex = RegExp(r'^[A-Z]{3}\s?\d{3,4}$');
    if (!plateRegex.hasMatch(trimmed)) {
      return const ValidationFailure('Please enter a valid plate number (e.g., ABC 123)');
    }
    return const ValidationSuccess();
  }

  /// Validates seat count
  static ValidationResult seatCount(int? value, {int maxSeats = 4}) {
    if (value == null) {
      return const ValidationFailure('Seat count is required');
    }
    if (value < 1) {
      return const ValidationFailure('At least 1 seat must be selected');
    }
    if (value > maxSeats) {
      return ValidationFailure('Cannot book more than $maxSeats seats');
    }
    return const ValidationSuccess();
  }

  /// Validates coordinates are within reasonable bounds
  static ValidationResult coordinates(LatLng? coords) {
    if (coords == null) {
      return const ValidationFailure('Location is required');
    }
    if (coords.latitude < minLat || coords.latitude > maxLat) {
      return const ValidationFailure('Location is outside service area');
    }
    if (coords.longitude < minLng || coords.longitude > maxLng) {
      return const ValidationFailure('Location is outside service area');
    }
    return const ValidationSuccess();
  }

  /// Validates fare amount
  static ValidationResult fareAmount(double? value) {
    if (value == null) {
      return const ValidationFailure('Fare is required');
    }
    if (value < 0) {
      return const ValidationFailure('Fare cannot be negative');
    }
    if (value > 10000) {
      return const ValidationFailure('Fare exceeds maximum allowed amount');
    }
    return const ValidationSuccess();
  }

  /// Validates vehicle capacity
  static ValidationResult vehicleCapacity(int? value) {
    if (value == null) {
      return const ValidationFailure('Capacity is required');
    }
    if (value < 1) {
      return const ValidationFailure('Capacity must be at least 1');
    }
    if (value > 20) {
      return const ValidationFailure('Capacity cannot exceed 20 passengers');
    }
    return const ValidationSuccess();
  }

  /// Validates that a value is not empty
  static ValidationResult notEmpty(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return ValidationFailure('$fieldName is required');
    }
    return const ValidationSuccess();
  }

  /// Validates a URL
  static ValidationResult url(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const ValidationFailure('URL is required');
    }
    final urlRegex = RegExp(
      r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&\/=]*)$',
    );
    if (!urlRegex.hasMatch(value)) {
      return const ValidationFailure('Please enter a valid URL');
    }
    return const ValidationSuccess();
  }

  /// Validates rating (1-5 stars)
  static ValidationResult rating(int? value) {
    if (value == null) {
      return const ValidationFailure('Rating is required');
    }
    if (value < 1 || value > 5) {
      return const ValidationFailure('Rating must be between 1 and 5 stars');
    }
    return const ValidationSuccess();
  }

  /// Validates file size (in bytes)
  static ValidationResult fileSize(int? bytes, {int maxSizeInMB = 5}) {
    if (bytes == null) {
      return const ValidationFailure('File size is required');
    }
    final maxSizeInBytes = maxSizeInMB * 1024 * 1024;
    if (bytes > maxSizeInBytes) {
      return ValidationFailure('File size must not exceed $maxSizeInMB MB');
    }
    return const ValidationSuccess();
  }

  /// Validates image file type
  static ValidationResult imageFileType(String? fileName) {
    if (fileName == null || fileName.isEmpty) {
      return const ValidationFailure('File name is required');
    }
    final extension = fileName.split('.').last.toLowerCase();
    const validExtensions = ['jpg', 'jpeg', 'png', 'webp', 'gif'];
    if (!validExtensions.contains(extension)) {
      return ValidationFailure('Invalid file type. Allowed: ${validExtensions.join(', ')}');
    }
    return const ValidationSuccess();
  }
}

/// Extension to easily check validation results on form fields
extension ValidationResultExtensions on ValidationResult {
  /// Returns null if valid, otherwise returns the error message (for form validation)
  String? get errorOrNull => isInvalid ? errorMessage : null;
}
