import 'package:flutter/material.dart';
import 'package:godavao/common/empty_state.dart';

class ErrorStateCard extends StatelessWidget {
  final String title;
  final String message;
  final String? ctaLabel;
  final VoidCallback? onCta;

  const ErrorStateCard({
    super.key,
    required this.title,
    required this.message,
    this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyStateCard(
      icon: Icons.error_outline,
      title: title,
      subtitle: message,
      ctaLabel: ctaLabel,
      onCta: onCta,
    );
  }
}
