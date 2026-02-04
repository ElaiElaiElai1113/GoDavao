import 'package:flutter/material.dart';

class PendingVerificationBanner extends StatelessWidget {
  const PendingVerificationBanner({
    super.key,
    required this.role, // 'driver' | 'passenger'
    this.submittedAt, // optional timestamp
    this.onReviewTap, // e.g. open VerifyIdentitySheet to update docs
  });

  final String role;
  final DateTime? submittedAt;
  final VoidCallback? onReviewTap;

  @override
  Widget build(BuildContext context) {
    final dateText =
        submittedAt != null ? ' Submitted: ${_fmtDate(submittedAt!)}.' : '';
    final roleLine =
        role == 'driver'
            ? 'You can browse the app, but cannot accept rides until approved.'
            : 'You can keep using the app while we review your documents.';

    return Container(
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top, color: Colors.orange, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your verification is pending.$dateText\n'
              'Reviews typically take 24–48 hours. $roleLine',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: onReviewTap,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Review',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    // Short, safe format (no intl dependency here)
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}
