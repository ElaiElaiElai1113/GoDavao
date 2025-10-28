import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final int value;
  final int max;
  final void Function(int)? onChanged;
  final double size;
  final bool readOnly;

  const StarRating({
    super.key,
    required this.value,
    this.max = 5,
    this.onChanged,
    this.size = 28,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(max, (i) {
        final idx = i + 1;
        final filled = idx <= value;

        return InkWell(
          onTap: readOnly ? null : () => onChanged?.call(idx),
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            size: size,
            color: filled
                ? Colors.amber.shade700
                : Colors.grey.shade400,
          ),
        );
      }),
    );
  }
}
