import 'package:flutter/material.dart';
import '../data/vehicle.dart';
import 'vehicle_status_chip.dart';

class VehicleCard extends StatelessWidget {
  final Vehicle v;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onMakePrimary;

  const VehicleCard({
    super.key,
    required this.v,
    this.onEdit,
    this.onDelete,
    this.onMakePrimary,
  });

  @override
  Widget build(BuildContext context) {
    final title = '${v.make} ${v.model}';
    final subtitleParts = <String>[
      v.plate,
      if (v.color?.isNotEmpty == true) v.color!,
      if (v.year != null) '${v.year}',
      if (v.seats != null) '${v.seats} seats',
    ];
    final subtitle = subtitleParts.join(' • ');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF1FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.directions_car,
                color: Color(0xFF3A3F73),
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (v.isPrimary)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'PRIMARY',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      VehicleStatusChip(status: v.verificationStatus),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              onSelected: (val) {
                switch (val) {
                  case 'primary':
                    onMakePrimary?.call();
                    break;
                  case 'edit':
                    onEdit?.call();
                    break;
                  case 'delete':
                    onDelete?.call();
                    break;
                }
              },
              itemBuilder:
                  (_) => [
                    if (!v.isPrimary)
                      const PopupMenuItem(
                        value: 'primary',
                        child: Text('Make Primary'),
                      ),
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
            ),
          ],
        ),
      ),
    );
  }
}
