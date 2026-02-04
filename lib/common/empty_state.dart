import 'package:flutter/material.dart';

class EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final bool compact;
  final bool showSubtitle;

  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
    this.compact = false,
    this.showSubtitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.grey.shade500, size: compact ? 20 : 36),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style:
                compact
                    ? Theme.of(context).textTheme.bodyMedium
                    : Theme.of(context).textTheme.titleSmall,
          ),
          if (showSubtitle) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ],
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onCta,
              icon: const Icon(Icons.arrow_forward),
              label: Text(ctaLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
