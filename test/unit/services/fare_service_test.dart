import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:godavao/core/fare_service.dart';

// Note: OSRM mocking removed as we're testing the fallback behavior

void main() {
  group('FareService', () {
    late FareService fareService;

    setUp(() {
      fareService = FareService();
    });

    group('estimateForDistance', () {
      test('calculates correct fare for basic ride', () {
        final result = fareService.estimateForDistance(
          distanceKm: 5.0,
          durationMin: 15.0,
          seats: 1,
        );

        expect(result.total, greaterThan(0));
        expect(result.distanceKm, 5.0);
        expect(result.durationMin, 15.0);
        expect(result.seatsBilled, 1);
      });

      test('applies minimum fare correctly', () {
        final result = fareService.estimateForDistance(
          distanceKm: 0.5,
          durationMin: 1.0,
          seats: 1,
        );

        expect(result.total, greaterThanOrEqualTo(fareService.rules.minFare));
      });

      test('applies night surcharge correctly', () {
        final nightTime = DateTime(2024, 1, 1, 22, 0); // 10 PM
        final dayTime = DateTime(2024, 1, 1, 14, 0); // 2 PM

        final nightResult = fareService.estimateForDistance(
          distanceKm: 5.0,
          durationMin: 15.0,
          when: nightTime,
          seats: 1,
        );

        final dayResult = fareService.estimateForDistance(
          distanceKm: 5.0,
          durationMin: 15.0,
          when: dayTime,
          seats: 1,
        );

        expect(nightResult.nightSurcharge, greaterThan(0));
        expect(dayResult.nightSurcharge, 0);
        expect(nightResult.total, greaterThan(dayResult.total));
      });

      test('applies surge multiplier correctly', () {
        final normalResult = fareService.estimateForDistance(
          distanceKm: 5.0,
          durationMin: 15.0,
          seats: 1,
          surgeMultiplier: 1.0,
        );

        final surgedResult = fareService.estimateForDistance(
          distanceKm: 5.0,
          durationMin: 15.0,
          seats: 1,
          surgeMultiplier: 1.5,
        );

        expect(surgedResult.surgeMultiplier, 1.5);
        expect(surgedResult.total, greaterThan(normalResult.total));
      });

      test('clamps surge multiplier to min/max bounds', () {
        final minResult = fareService.estimateForDistance(
          distanceKm: 5.0,
          durationMin: 15.0,
          seats: 1,
          surgeMultiplier: 0.5, // Below min
        );

        final maxResult = fareService.estimateForDistance(
          distanceKm: 5.0,
          durationMin: 15.0,
          seats: 1,
          surgeMultiplier: 3.0, // Above max
        );

        expect(minResult.surgeMultiplier, fareService.rules.minSurgeMultiplier);
        expect(maxResult.surgeMultiplier, fareService.rules.maxSurgeMultiplier);
      });

      test('bills multiple seats correctly', () {
        final singleSeat = fareService.estimateForDistance(
          distanceKm: 5.0,
          durationMin: 15.0,
          seats: 1,
        );

        final threeSeats = fareService.estimateForDistance(
          distanceKm: 5.0,
          durationMin: 15.0,
          seats: 3,
        );

        expect(threeSeats.seatsBilled, 3);
        expect(threeSeats.total, greaterThan(singleSeat.total));
      });

      test('applies carpool discount correctly', () {
        final noCarpool = fareService.estimateForDistance(
          distanceKm: 10.0,
          durationMin: 30.0,
          seats: 1,
          carpoolSeats: 1,
        );

        final withCarpool = fareService.estimateForDistance(
          distanceKm: 10.0,
          durationMin: 30.0,
          seats: 1,
          carpoolSeats: 3,
        );

        expect(withCarpool.carpoolSeats, 3);
        expect(withCarpool.carpoolDiscountPct, greaterThan(0));
        expect(withCarpool.total, lessThan(noCarpool.total));
      });

      test('handles group flat pricing mode', () {
        final shared = fareService.estimateForDistance(
          distanceKm: 10.0,
          durationMin: 30.0,
          seats: 4,
          mode: PricingMode.shared,
        );

        final groupFlat = fareService.estimateForDistance(
          distanceKm: 10.0,
          durationMin: 30.0,
          seats: 4,
          mode: PricingMode.groupFlat,
        );

        expect(groupFlat.seatsBilled, 1);
        expect(shared.seatsBilled, 4);
        expect(groupFlat.mode, PricingMode.groupFlat);
      });

      test('handles pakyaw pricing mode', () {
        final result = fareService.estimateForDistance(
          distanceKm: 10.0,
          durationMin: 30.0,
          seats: 4,
          mode: PricingMode.pakyaw,
        );

        expect(result.mode, PricingMode.pakyaw);
        expect(result.seatsBilled, 4);
      });

      test('calculates platform fee correctly', () {
        final result = fareService.estimateForDistance(
          distanceKm: 10.0,
          durationMin: 30.0,
          seats: 1,
        );

        expect(result.platformFee, greaterThan(0));
        expect(result.driverTake, greaterThan(0));
        expect(result.total, result.platformFee + result.driverTake);
      });

      test('uses custom platform fee rate', () {
        final defaultRate = fareService.estimateForDistance(
          distanceKm: 10.0,
          durationMin: 30.0,
          seats: 1,
        );

        final customRate = fareService.estimateForDistance(
          distanceKm: 10.0,
          durationMin: 30.0,
          seats: 1,
          platformFeeRate: 0.10, // 10% instead of default 15%
        );

        expect(customRate.platformFee, lessThan(defaultRate.platformFee));
      });
    });

    group('FareBreakdown.toMap', () {
      test('converts breakdown to map correctly', () {
        final result = fareService.estimateForDistance(
          distanceKm: 5.0,
          durationMin: 15.0,
          seats: 1,
        );

        final map = result.toMap();

        expect(map['distance_km'], 5.0);
        expect(map['duration_min'], 15.0);
        expect(map['seats_billed'], 1);
        expect(map['mode'], 'shared');
        expect(map.containsKey('total'), true);
        expect(map.containsKey('platform_fee'), true);
        expect(map.containsKey('driver_take'), true);
      });
    });

    group('FareRules defaults', () {
      test('has sensible default values', () {
        final rules = fareService.rules;

        expect(rules.baseFare, 25.0);
        expect(rules.perKm, 14.0);
        expect(rules.perMin, 0.8);
        expect(rules.minFare, 70.0);
        expect(rules.bookingFee, 5.0);
        expect(rules.nightSurchargePct, 0.15);
        expect(rules.defaultPlatformFeeRate, 0.15);
      });
    });

    group('estimate with async OSRM', () {
      test('fallback to Haversine when OSRM fails', () async {
        final pickup = LatLng(7.0711, 125.6088); // Davao City coordinates
        final destination = LatLng(7.0652, 125.6126);

        // This should use Haversine fallback if OSRM is not available
        final result = await fareService.estimate(
          pickup: pickup,
          destination: destination,
          seats: 1,
        );

        expect(result.total, greaterThan(0));
        expect(result.distanceKm, greaterThan(0));
      });
    });
  });
}
