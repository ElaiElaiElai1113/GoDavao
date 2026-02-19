import 'package:flutter/material.dart';
import 'package:godavao/features/rides/data/fare_calculator.dart';

class FareBreakdownRow extends StatelessWidget {
  final FareBreakdown breakdown;

  const FareBreakdownRow({super.key, required this.breakdown});

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    Color? color,
    FontWeight weight = FontWeight.normal,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: color, fontWeight: weight),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: color, fontWeight: weight),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row(
          context,
          'Base fare',
          'â‚±${breakdown.baseFare.toStringAsFixed(2)}',
        ),
        _row(
          context,
          'Per km (${breakdown.km} km)',
          'â‚±${breakdown.perKmComponent.toStringAsFixed(2)}',
        ),
        _row(
          context,
          'Per min (${breakdown.minutes} min)',
          'â‚±${breakdown.perMinComponent.toStringAsFixed(2)}',
        ),
        _row(
          context,
          'Booking fee',
          'â‚±${breakdown.bookingFee.toStringAsFixed(2)}',
        ),
        if (breakdown.nightSurcharge > 0)
          _row(
            context,
            'Night surcharge (15%)',
            'â‚±${breakdown.nightSurcharge.toStringAsFixed(2)}',
            color: Colors.deepOrange,
          ),
        const Divider(),
        _row(
          context,
          'Total',
          'â‚±${breakdown.total.toStringAsFixed(2)}',
          weight: FontWeight.bold,
        ),
      ],
    );
  }
}
