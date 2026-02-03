import 'package:flutter/foundation.dart';

/// A type-safe Result type for handling operations that can fail.
/// This replaces throwing exceptions with explicit error handling.
///
/// Example:
/// ```dart
/// Result<User, ApiError> result = await userService.getUser(id);
/// result.when(
///   success: (user) => print('Got user: ${user.name}'),
///   failure: (error) => print('Error: ${error.message}'),
/// );
/// ```
@immutable
sealed class Result<S, F> {
  const Result();

  /// Returns true if this result is a success
  bool get isSuccess => this is Success<S, F>;

  /// Returns true if this result is a failure
  bool get isFailure => this is Failure<S, F>;

  /// Transforms the success value if this is a Success
  Result<T, F> map<T>(T Function(S success) transform) {
    if (this is Success<S, F>) {
      return Success(transform((this as Success<S, F>).value));
    }
    return Failure((this as Failure<S, F>).value);
  }

  /// Transforms the failure value if this is a Failure
  Result<S, T> mapFailure<T>(T Function(F failure) transform) {
    if (this is Failure<S, F>) {
      return Failure(transform((this as Failure<S, F>).value));
    }
    return Success((this as Success<S, F>).value);
  }

  /// Executes one of the provided callbacks based on the result type
  T when<T>({
    required T Function(S success) success,
    required T Function(F failure) failure,
  }) {
    if (this is Success<S, F>) {
      return success((this as Success<S, F>).value);
    }
    return failure((this as Failure<S, F>).value);
  }

  /// Returns the success value or throws if this is a failure
  S getOrThrow() {
    return when(
      success: (value) => value,
      failure: (error) => throw ResultException(error.toString()),
    );
  }

  /// Returns the success value or a default value if this is a failure
  S getOrElse(S Function(F failure) defaultValue) {
    return when(
      success: (value) => value,
      failure: defaultValue,
    );
  }

  /// Returns the success value or null if this is a failure
  S? getOrNull() {
    return when(
      success: (value) => value,
      failure: (_) => null,
    );
  }
}

/// Represents a successful operation with a value of type [S]
final class Success<S, F> extends Result<S, F> {
  final S value;
  const Success(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Success<S, F> &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Success($value)';
}

/// Represents a failed operation with a failure value of type [F]
final class Failure<S, F> extends Result<S, F> {
  final F value;
  const Failure(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure<S, F> &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Failure($value)';
}

/// Exception thrown when [getOrThrow] is called on a Failure
class ResultException implements Exception {
  final String message;
  ResultException(this.message);

  @override
  String toString() => 'ResultException: $message';
}

// Extension methods for convenience
extension ResultExtensions<S, F> on Result<S, F> {
  /// Chains operations that return Results
  Result<T, F> andThen<T>(Result<T, F> Function(S success) chain) {
    if (this is Success<S, F>) {
      return chain((this as Success<S, F>).value);
    }
    return Failure((this as Failure<S, F>).value);
  }

  /// Executes a side effect for success values
  Result<S, F> onSuccess(void Function(S success) effect) {
    when(
      success: effect,
      failure: (_) {},
    );
    return this;
  }

  /// Executes a side effect for failure values
  Result<S, F> onFailure(void Function(F failure) effect) {
    when(
      success: (_) {},
      failure: effect,
    );
    return this;
  }

  /// Recovers from a failure by transforming it into a success
  Result<S, F> recoverWith(Result<S, F> Function(F failure) recover) {
    if (this is Success<S, F>) {
      return this;
    }
    return recover((this as Failure<S, F>).value);
  }
}

/// Helper extension to create Results from potentially throwing functions
extension ResultTryExtensions<T> on T Function() {
  Result<T, Exception> tryGet() {
    try {
      final result = this();
      return Success(result);
    } catch (e) {
      return Failure(e is Exception ? e : Exception(e.toString()));
    }
  }
}

/// Helper extension to create Results from async potentially throwing functions
extension AsyncResultTryExtensions<T> on Future<T> Function() {
  Future<Result<T, Exception>> tryGet() async {
    try {
      final result = await this();
      return Success(result);
    } catch (e) {
      return Failure(e is Exception ? e : Exception(e.toString()));
    }
  }
}
