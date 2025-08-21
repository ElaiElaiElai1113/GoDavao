import 'dart:math' as math;
import 'package:flutter/material.dart';

class DriverMarker extends StatelessWidget {
  const DriverMarker({
    super.key,
    required this.size,
    required this.headingDeg,
    this.active = true,
    this.color = const Color(0xFF2962FF),
    this.icon = Icons.directions_car_filled_rounded,
    this.label,
  });

  /// Visual size of the marker widget (square).
  final double size;

  /// Heading in degrees (0..360), where 0 is pointing up (north).
  final double headingDeg;

  /// Whether to show the pulse ring.
  final bool active;

  /// Base color of the marker.
  final Color color;

  /// Icon to render for the vehicle.
  final IconData icon;

  /// Optional small label under the marker (e.g., plate).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final angleRad = headingDeg * math.pi / 180.0;

    final marker = Stack(
      alignment: Alignment.center,
      children: [
        // Pulse ring
        if (active)
          _PulsingRing(
            color: color.withOpacity(0.25),
            maxRadius: size * 0.9,
            minRadius: size * 0.7,
            duration: const Duration(seconds: 2),
          ),

        // Rotating car icon inside a circular chip
        Transform.rotate(
          angle: angleRad,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: color, size: size * 0.6),
          ),
        ),
      ],
    );

    if (label == null || label!.isEmpty) return marker;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        marker,
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            label!,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

class _PulsingRing extends StatefulWidget {
  const _PulsingRing({
    required this.color,
    required this.maxRadius,
    required this.minRadius,
    required this.duration,
  });

  final Color color;
  final double maxRadius;
  final double minRadius;
  final Duration duration;

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat();
  late final Animation<double> _t = CurvedAnimation(
    parent: _ac,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (_, __) {
        final r =
            widget.minRadius + (widget.maxRadius - widget.minRadius) * _t.value;
        final opacity = (1.0 - _t.value) * 0.7;
        return Container(
          width: r,
          height: r,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(opacity),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
