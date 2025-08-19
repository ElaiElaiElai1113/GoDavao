import 'package:flutter/material.dart';
import 'package:godavao/features/rides/data/fare_calculator.dart';

class FareBreakdownRow extends StatelessWidget {
  final FareBreakdown breakdown;

  const FareBreakdownRow({super.key, required this.breakdown});

  Widget _row(
    String label,
    String value, {
    Color? color,
    FontWeight weight = FontWeight.normal,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: color)),
        Text(value, style: TextStyle(fontWeight: weight, color: color)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row("Base fare", "₱${breakdown.baseFare.toStringAsFixed(2)}"),
        _row(
          "Per km (${breakdown.km} km)",
          "₱${breakdown.perKmComponent.toStringAsFixed(2)}",
        ),
        _row(
          "Per min (${breakdown.minutes} min)",
          "₱${breakdown.perMinComponent.toStringAsFixed(2)}",
        ),
        _row("Booking fee", "₱${breakdown.bookingFee.toStringAsFixed(2)}"),
        if (breakdown.nightSurcharge > 0)
          _row(
            "Night surcharge (15%)",
            "₱${breakdown.nightSurcharge.toStringAsFixed(2)}",
            color: Colors.deepOrange,
          ),
        const Divider(),
        _row(
          "Total",
          "₱${breakdown.total.toStringAsFixed(2)}",
          weight: FontWeight.bold,
        ),
      ],
    );
  }
}
