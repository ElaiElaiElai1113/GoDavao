import 'package:flutter/material.dart';

/// Compact stars row like: 4.8 ★ (123)

class RatingBadge extends StatelessWidget {
  final double? avg;
  final int? count;
  final double iconSize;
  final TextStyle? textStyle;
  final bool dense;

  const RatingBadge({
    super.key,
    required this.avg,
    required this.count,
    this.iconSize = 14,
    this.textStyle,
    this.dense = true,
  });

  @override
  Widget build(BuildContext context) {
    if (avg == null || avg!.isNaN) {
      return Text(
        'No ratings',
        style: textStyle ?? Theme.of(context).textTheme.bodySmall,
      );
    }

    final style = textStyle ?? Theme.of(context).textTheme.bodySmall;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(avg!.toStringAsFixed(2), style: style),
        SizedBox(width: dense ? 4 : 6),
        Icon(Icons.star, size: iconSize),
        SizedBox(width: dense ? 4 : 6),
        Text('(${(count ?? 0)})', style: style),
      ],
    );
  }
}
