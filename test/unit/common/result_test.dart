import 'package:flutter_test/flutter_test.dart';
import 'package:godavao/common/result.dart';

void main() {
  group('Result', () {
    group('Success', () {
      test('stores value correctly', () {
        final result = Success<int, String>(42);
        expect(result.value, 42);
        expect(result.isSuccess, true);
        expect(result.isFailure, false);
      });

      test('equality works correctly', () {
        final result1 = Success<int, String>(42);
        final result2 = Success<int, String>(42);
        final result3 = Success<int, String>(43);

        expect(result1, equals(result2));
        expect(result1, isNot(equals(result3)));
      });

      test('toString returns correct format', () {
        final result = Success<int, String>(42);
        expect(result.toString(), 'Success(42)');
      });
    });

    group('Failure', () {
      test('stores error correctly', () {
        final result = Failure<int, String>('error');
        expect(result.value, 'error');
        expect(result.isSuccess, false);
        expect(result.isFailure, true);
      });

      test('equality works correctly', () {
        final result1 = Failure<int, String>('error');
        final result2 = Failure<int, String>('error');
        final result3 = Failure<int, String>('other');

        expect(result1, equals(result2));
        expect(result1, isNot(equals(result3)));
      });

      test('toString returns correct format', () {
        final result = Failure<int, String>('error');
        expect(result.toString(), 'Failure(error)');
      });
    });

    group('Result methods', () {
      test('map transforms success value', () {
        final result = Success<int, String>(5);
        final doubled = result.map((value) => value * 2);

        expect(doubled, isA<Success<int, String>>());
        expect((doubled as Success<int, String>).value, 10);
      });

      test('map does not transform failure', () {
        final result = Failure<int, String>('error');
        final mapped = result.map((value) => value * 2);

        expect(mapped, isA<Failure<int, String>>());
        expect((mapped as Failure<int, String>).value, 'error');
      });

      test('mapFailure transforms failure value', () {
        final result = Failure<int, String>('error');
        final mapped = result.mapFailure((err) => 'ERROR: $err');

        expect(mapped, isA<Failure<int, int>>());
        expect((mapped as Failure<int, int>).value, 'ERROR: error');
      });

      test('mapFailure does not transform success', () {
        final result = Success<int, String>(5);
        final mapped = result.mapFailure((err) => 999);

        expect(mapped, isA<Success<int, int>>());
        expect((mapped as Success<int, int>).value, 5);
      });

      test('when executes success callback', () {
        final result = Success<int, String>(42);
        var executed = '';

        result.when(
          success: (value) {
            executed = 'success: $value';
          },
          failure: (error) {
            executed = 'failure: $error';
          },
        );

        expect(executed, 'success: 42');
      });

      test('when executes failure callback', () {
        final result = Failure<int, String>('error');
        var executed = '';

        result.when(
          success: (value) {
            executed = 'success: $value';
          },
          failure: (error) {
            executed = 'failure: $error';
          },
        );

        expect(executed, 'failure: error');
      });

      test('getOrThrow returns value for success', () {
        final result = Success<int, String>(42);
        expect(result.getOrThrow(), 42);
      });

      test('getOrThrow throws for failure', () {
        final result = Failure<int, String>('error');
        expect(
          () => result.getOrThrow(),
          throwsA(isA<ResultException>()),
        );
      });

      test('getOrElse returns value for success', () {
        final result = Success<int, String>(42);
        expect(result.getOrElse((error) => 0), 42);
      });

      test('getOrElse returns default for failure', () {
        final result = Failure<int, String>('error');
        expect(result.getOrElse((error) => 0), 0);
      });

      test('getOrNull returns value for success', () {
        final result = Success<int, String>(42);
        expect(result.getOrNull(), 42);
      });

      test('getOrNull returns null for failure', () {
        final result = Failure<int, String>('error');
        expect(result.getOrNull(), null);
      });
    });

    group('ResultExtensions', () {
      test('andThen chains successful operations', () async {
        final result = Success<int, String>(5);
        final chained = result.andThen((value) => Success<int, String>(value * 2));

        expect(chained.isSuccess, true);
        expect((chained as Success).value, 10);
      });

      test('andThen returns failure on first error', () {
        final result = Failure<int, String>('error');
        final chained = result.andThen((value) => Success<int, String>(value * 2));

        expect(chained.isFailure, true);
      });

      test('onSuccess executes callback for success', () {
        final result = Success<int, String>(42);
        var executed = false;

        result.onSuccess((value) {
          executed = true;
          expect(value, 42);
        });

        expect(executed, true);
      });

      test('onSuccess does not execute for failure', () {
        final result = Failure<int, String>('error');
        var executed = false;

        result.onSuccess((value) {
          executed = true;
        });

        expect(executed, false);
      });

      test('onFailure executes callback for failure', () {
        final result = Failure<int, String>('error');
        var executed = false;

        result.onFailure((error) {
          executed = true;
          expect(error, 'error');
        });

        expect(executed, true);
      });

      test('onFailure does not execute for success', () {
        final result = Success<int, String>(42);
        var executed = false;

        result.onFailure((error) {
          executed = true;
        });

        expect(executed, false);
      });

      test('recoverWith transforms failure to success', () {
        final result = Failure<int, String>('error');
        final recovered = result.recoverWith(
          (error) => Success<int, String>(0),
        );

        expect(recovered.isSuccess, true);
        expect((recovered as Success).value, 0);
      });

      test('recoverWith does not transform success', () {
        final result = Success<int, String>(42);
        final recovered = result.recoverWith(
          (error) => Success<int, String>(0),
        );

        expect(recovered.isSuccess, true);
        expect((recovered as Success).value, 42);
      });
    });

    group('ResultTryExtensions', () {
      test('tryGet returns Success for successful function', () {
        int Function() fn = () => 42;
        final result = fn.tryGet();

        expect(result.isSuccess, true);
        expect((result as Success).value, 42);
      });

      test('tryGet returns Failure for throwing function', () {
        int Function() fn = () => throw Exception('error');
        final result = fn.tryGet();

        expect(result.isFailure, true);
        expect((result as Failure).value, isA<Exception>());
      });
    });

    group('AsyncResultTryExtensions', () {
      test('tryGet returns Success for successful async function', () async {
        Future<int> Function() fn = () async => 42;
        final result = await fn.tryGet();

        expect(result.isSuccess, true);
        expect((result as Success).value, 42);
      });

      test('tryGet returns Failure for throwing async function', () async {
        Future<int> Function() fn = () async => throw Exception('error');
        final result = await fn.tryGet();

        expect(result.isFailure, true);
        expect((result as Failure).value, isA<Exception>());
      });
    });

    group('Result usage patterns', () {
      test('can chain multiple operations', () {
        final result = Success<int, String>(5)
            .map((v) => v * 2)
            .map((v) => v + 10);

        expect((result as Success).value, 20);
      });

      test('can use andThen for dependent operations', () {
        final result = Success<int, String>(5).andThen((value) {
          if (value > 0) {
            return Success<int, String>(value * 2);
          } else {
            return Failure<int, String>('must be positive');
          }
        });

        expect((result as Success).value, 10);
      });

      test('can use recoverWith to provide fallbacks', () {
        final result = Failure<int, String>('error').recoverWith((error) {
          return Success<int, String>(0);
        });

        expect((result as Success).value, 0);
      });
    });
  });
}
