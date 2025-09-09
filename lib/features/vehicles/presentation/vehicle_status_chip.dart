import 'package:flutter/material.dart';

class VehicleStatusChip extends StatelessWidget {
  final String status; // pending | verified | rejected
  const VehicleStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color c;
    String text;
    switch (s) {
      case 'verified':
        c = Colors.green;
        text = 'VERIFIED';
        break;
      case 'rejected':
        c = Colors.red;
        text = 'REJECTED';
        break;
      default:
        c = Colors.orange;
        text = 'PENDING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }
}
