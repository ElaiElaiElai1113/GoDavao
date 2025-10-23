import 'package:flutter/material.dart';
import 'sos_sheet.dart';

Future<void> showSosSheet(BuildContext context, {String? rideId}) {
  return showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SosSheet(rideId: rideId),
  );
}

/// Reusable SOS button (small)
class SosIconButton extends StatelessWidget {
  final String? rideId;
  const SosIconButton({super.key, this.rideId});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.emergency_share_outlined),
      tooltip: 'Safety (SOS)',
      onPressed: () => showSosSheet(context, rideId: rideId),
    );
  }
}

/// Reusable SOS button (prominent)
class SosPillButton extends StatelessWidget {
  final String? rideId;
  const SosPillButton({super.key, this.rideId});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: const Icon(Icons.warning_amber_rounded),
      label: const Text('SOS'),
      style: FilledButton.styleFrom(backgroundColor: Colors.red),
      onPressed: () => showSosSheet(context, rideId: rideId),
    );
  }
}
