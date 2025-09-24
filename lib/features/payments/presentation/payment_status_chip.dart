import 'package:flutter/material.dart';

class PaymentStatusChip extends StatelessWidget {
  final String? status; // on_hold | captured | canceled | requires_proof | null
  final double? amount;

  const PaymentStatusChip({super.key, this.status, this.amount});

  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox.shrink();
    late final Color bg;
    late final IconData icon;
    late final String label;

    switch (status) {
      case 'on_hold':
        bg = Color(0xFF6A27F7);
        icon = Icons.lock_clock;
        label = 'ON HOLD';
        break;
      case 'captured':
        bg = Colors.green.shade100;
        icon = Icons.verified;
        label = 'CAPTURED';
        break;
      case 'canceled':
        bg = Colors.red.shade100;
        icon = Icons.cancel;
        label = 'CANCELED';
        break;
      case 'requires_proof':
        bg = Colors.blueGrey.shade100;
        icon = Icons.hourglass_top;
        label = 'REQUIRES PROOF';
        break;
      default:
        bg = Colors.grey.shade200;
        icon = Icons.help_outline;
        label = status!.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (amount != null) ...[
            const SizedBox(width: 6),
            Text(
              '₱${amount!.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
