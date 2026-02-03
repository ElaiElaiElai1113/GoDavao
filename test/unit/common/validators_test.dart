import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:godavao/common/validators.dart';

void main() {
  group('Validators', () {
    group('name validation', () {
      test('accepts valid names', () {
        expect(Validators.name('Juan Dela Cruz').isValid, true);
        expect(Validators.name('Maria').isValid, true);
        expect(Validators.name("O'Neil").isValid, true);
        expect(Validators.name('Anne-Marie').isValid, true);
      });

      test('rejects empty names', () {
        expect(Validators.name('').isInvalid, true);
        expect(Validators.name('   ').isInvalid, true);
        expect(Validators.name(null).isInvalid, true);
      });

      test('rejects names that are too short', () {
        expect(Validators.name('J').isInvalid, true);
      });

      test('rejects names that are too long', () {
        expect(Validators.name('A' * 51).isInvalid, true);
      });

      test('rejects names with invalid characters', () {
        expect(Validators.name('John123').isInvalid, true);
        expect(Validators.name('John@Doe').isInvalid, true);
      });
    });

    group('email validation', () {
      test('accepts valid emails', () {
        expect(Validators.email('test@example.com').isValid, true);
        expect(Validators.email('user.name@domain.co').isValid, true);
        expect(Validators.email('user+tag@example.com').isValid, true);
      });

      test('rejects invalid emails', () {
        expect(Validators.email('invalid').isInvalid, true);
        expect(Validators.email('@example.com').isInvalid, true);
        expect(Validators.email('user@').isInvalid, true);
        expect(Validators.email('user..name@example.com').isInvalid, true);
      });

      test('rejects empty emails', () {
        expect(Validators.email('').isInvalid, true);
        expect(Validators.email(null).isInvalid, true);
      });

      test('normalizes email to lowercase', () {
        final result = Validators.email('TEST@EXAMPLE.COM');
        expect(result.isValid, true);
      });
    });

    group('phone number validation', () {
      test('accepts valid Philippine mobile numbers', () {
        expect(Validators.phoneNumber('09171234567').isValid, true);
        expect(Validators.phoneNumber('09123456789').isValid, true);
        expect(Validators.phoneNumber('+639171234567').isValid, true);
        expect(Validators.phoneNumber('639171234567').isValid, true);
        expect(Validators.phoneNumber('0912-345-6789').isValid, true);
        expect(Validators.phoneNumber('(0912) 345-6789').isValid, true);
      });

      test('rejects invalid phone numbers', () {
        expect(Validators.phoneNumber('12345').isInvalid, true);
        expect(Validators.phoneNumber('08123456789').isInvalid, true); // Starts with 08
        expect(Validators.phoneNumber('0912345678').isInvalid, true); // Too short
        expect(Validators.phoneNumber('091234567890').isInvalid, true); // Too long
      });

      test('rejects empty phone numbers', () {
        expect(Validators.phoneNumber('').isInvalid, true);
        expect(Validators.phoneNumber(null).isInvalid, true);
      });
    });

    group('password validation', () {
      test('accepts valid passwords', () {
        expect(Validators.password('Password123').isValid, true);
        expect(Validators.password('Test1234').isValid, true);
        expect(Validators.password('abc123XYZ').isValid, true);
      });

      test('rejects passwords without letters', () {
        expect(Validators.password('12345678').isInvalid, true);
      });

      test('rejects passwords without numbers', () {
        expect(Validators.password('Password').isInvalid, true);
      });

      test('rejects passwords that are too short', () {
        expect(Validators.password('Pass1').isInvalid, true);
      });

      test('rejects empty passwords', () {
        expect(Validators.password('').isInvalid, true);
        expect(Validators.password(null).isInvalid, true);
      });
    });

    group('address validation', () {
      test('accepts valid addresses', () {
        expect(Validators.address('123 Main St, Davao City').isValid, true);
        expect(Validators.address('Bago Oshiro, Davao City').isValid, true);
      });

      test('rejects addresses that are too short', () {
        expect(Validators.address('123').isInvalid, true);
      });

      test('rejects empty addresses', () {
        expect(Validators.address('').isInvalid, true);
        expect(Validators.address(null).isInvalid, true);
      });
    });

    group('plate number validation', () {
      test('accepts valid Philippine plate numbers', () {
        expect(Validators.plateNumber('ABC 123').isValid, true);
        expect(Validators.plateNumber('XYZ 1234').isValid, true);
        expect(Validators.plateNumber('abc 123').isValid, true); // Lowercase
      });

      test('rejects invalid plate numbers', () {
        expect(Validators.plateNumber('123 ABC').isInvalid, true);
        expect(Validators.plateNumber('ABCD 123').isInvalid, true);
        expect(Validators.plateNumber('ABC 12').isInvalid, true);
      });

      test('rejects empty plate numbers', () {
        expect(Validators.plateNumber('').isInvalid, true);
        expect(Validators.plateNumber(null).isInvalid, true);
      });
    });

    group('seat count validation', () {
      test('accepts valid seat counts', () {
        expect(Validators.seatCount(1).isValid, true);
        expect(Validators.seatCount(2).isValid, true);
        expect(Validators.seatCount(4).isValid, true);
      });

      test('rejects invalid seat counts', () {
        expect(Validators.seatCount(0).isInvalid, true);
        expect(Validators.seatCount(-1).isInvalid, true);
      });

      test('respects max seats limit', () {
        expect(Validators.seatCount(5, maxSeats: 4).isInvalid, true);
        expect(Validators.seatCount(4, maxSeats: 4).isValid, true);
      });

      test('rejects null seat count', () {
        expect(Validators.seatCount(null).isInvalid, true);
      });
    });

    group('coordinates validation', () {
      test('accepts valid Davao City coordinates', () {
        expect(Validators.coordinates(LatLng(7.07, 125.61)).isValid, true);
        expect(Validators.coordinates(LatLng(7.0, 125.5)).isValid, true);
      });

      test('rejects coordinates outside service area', () {
        expect(
          Validators.coordinates(LatLng(14.6, 121.0)).isInvalid, true, // Manila
        );
        expect(
          Validators.coordinates(LatLng(0, 0)).isInvalid, true,
        );
      });

      test('rejects null coordinates', () {
        expect(Validators.coordinates(null).isInvalid, true);
      });
    });

    group('fare amount validation', () {
      test('accepts valid fare amounts', () {
        expect(Validators.fareAmount(0).isValid, true);
        expect(Validators.fareAmount(50).isValid, true);
        expect(Validators.fareAmount(100).isValid, true);
      });

      test('rejects negative fares', () {
        expect(Validators.fareAmount(-1).isInvalid, true);
      });

      test('rejects excessive fares', () {
        expect(Validators.fareAmount(20000).isInvalid, true);
      });

      test('rejects null fare', () {
        expect(Validators.fareAmount(null).isInvalid, true);
      });
    });

    group('vehicle capacity validation', () {
      test('accepts valid capacities', () {
        expect(Validators.vehicleCapacity(1).isValid, true);
        expect(Validators.vehicleCapacity(4).isValid, true);
        expect(Validators.vehicleCapacity(20).isValid, true);
      });

      test('rejects invalid capacities', () {
        expect(Validators.vehicleCapacity(0).isInvalid, true);
        expect(Validators.vehicleCapacity(-1).isInvalid, true);
      });

      test('rejects excessive capacities', () {
        expect(Validators.vehicleCapacity(25).isInvalid, true);
      });
    });

    group('URL validation', () {
      test('accepts valid URLs', () {
        expect(Validators.url('https://example.com').isValid, true);
        expect(Validators.url('http://example.com').isValid, true);
        expect(
          Validators.url('https://example.com/path?query=value').isValid,
          true,
        );
      });

      test('rejects invalid URLs', () {
        expect(Validators.url('example.com').isInvalid, true);
        expect(Validators.url('ftp://example.com').isInvalid, true);
      });

      test('rejects empty URLs', () {
        expect(Validators.url('').isInvalid, true);
        expect(Validators.url(null).isInvalid, true);
      });
    });

    group('rating validation', () {
      test('accepts valid ratings', () {
        expect(Validators.rating(1).isValid, true);
        expect(Validators.rating(3).isValid, true);
        expect(Validators.rating(5).isValid, true);
      });

      test('rejects invalid ratings', () {
        expect(Validators.rating(0).isInvalid, true);
        expect(Validators.rating(6).isInvalid, true);
        expect(Validators.rating(-1).isInvalid, true);
      });

      test('rejects null rating', () {
        expect(Validators.rating(null).isInvalid, true);
      });
    });

    group('file size validation', () {
      test('accepts valid file sizes', () {
        expect(Validators.fileSize(1024).isValid, true);
        expect(Validators.fileSize(5 * 1024 * 1024).isValid, true); // 5MB
      });

      test('rejects files that are too large', () {
        expect(
          Validators.fileSize(6 * 1024 * 1024).isInvalid, true, // 6MB
        );
      });

      test('respects custom max size', () {
        expect(
          Validators.fileSize(2 * 1024 * 1024, maxSizeInMB: 2).isValid,
          true,
        );
        expect(
          Validators.fileSize(3 * 1024 * 1024, maxSizeInMB: 2).isInvalid,
          true,
        );
      });
    });

    group('image file type validation', () {
      test('accepts valid image types', () {
        expect(Validators.imageFileType('photo.jpg').isValid, true);
        expect(Validators.imageFileType('photo.jpeg').isValid, true);
        expect(Validators.imageFileType('photo.png').isValid, true);
        expect(Validators.imageFileType('photo.webp').isValid, true);
        expect(Validators.imageFileType('photo.gif').isValid, true);
      });

      test('rejects invalid file types', () {
        expect(Validators.imageFileType('photo.pdf').isInvalid, true);
        expect(Validators.imageFileType('photo.doc').isInvalid, true);
        expect(Validators.imageFileType('photo').isInvalid, true);
      });
    });

    group('error messages', () {
      test('provide meaningful error messages', () {
        final emailResult = Validators.email('invalid');
        expect(
          emailResult.errorMessage,
          contains('valid email'),
        );

        final phoneResult = Validators.phoneNumber('123');
        expect(
          phoneResult.errorMessage,
          contains('valid Philippine mobile number'),
        );

        final passwordResult = Validators.password('short');
        expect(
          passwordResult.errorMessage,
          contains('at least'),
        );
      });
    });

    group('errorOrNull extension', () {
      test('returns null for valid results', () {
        expect(Validators.name('Valid Name').errorOrNull, null);
      });

      test('returns error message for invalid results', () {
        expect(Validators.name('').errorOrNull, isNotNull);
        expect(Validators.email('invalid').errorOrNull, isNotNull);
      });
    });
  });
}
