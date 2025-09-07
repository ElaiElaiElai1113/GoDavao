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
    this.mapRotationDeg =
        0, // ← if your map can rotate, pass the map’s rotation
    this.headingSmoothing = 0.25, // ← 0=none, 0.2–0.35 is mild smoothing
  });

  /// Visual size of the marker widget (square).
  final double size;

  /// Heading in degrees (0..360), where 0 is geographic north (up).
  final double headingDeg;

  /// Whether to show the pulse ring.
  final bool active;

  /// Base color of the marker.
  final Color color;

  /// Icon to render for the vehicle.
  final IconData icon;

  /// Optional small label under the marker (e.g., plate).
  final String? label;

  /// Degrees of map rotation (0 if north-up). If you rotate the map, set this so
  /// the icon still points the direction of travel visually.
  final double mapRotationDeg;

  /// 0..1 — how much to smooth heading frame-to-frame (cheap low-pass in an
  /// internal stateful wrapper).
  final double headingSmoothing;

  @override
  Widget build(BuildContext context) {
    // Normalize + compensate for map rotation
    final normalized = _norm(headingDeg);
    final visualHeading = _norm(normalized - mapRotationDeg);

    final marker = _SmoothedRotation(
      angleDeg: visualHeading,
      smoothing: headingSmoothing,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (active)
            _PulsingRing(
              color: color.withOpacity(0.25),
              maxRadius: size * 0.9,
              minRadius: size * 0.7,
              duration: const Duration(seconds: 2),
            ),

          // Rotating car icon inside a circular chip
          Container(
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
        ],
      ),
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 120,
            ), // safe on small screens
            child: Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _norm(double d) {
    if (d.isNaN || !d.isFinite) return 0;
    var x = d % 360;
    if (x < 0) x += 360;
    return x;
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

/// Smoothly rotates the child to the requested heading.
/// - Handles wrap-around (359° → 0°) via shortest-arc tweening.
/// - Optional low-pass to damp jitter from GPS headings.
class _SmoothedRotation extends StatefulWidget {
  const _SmoothedRotation({
    required this.child,
    required this.angleDeg,
    required this.smoothing,
  });

  final Widget child;
  final double angleDeg;
  final double smoothing;

  @override
  State<_SmoothedRotation> createState() => _SmoothedRotationState();
}

class _SmoothedRotationState extends State<_SmoothedRotation>
    with SingleTickerProviderStateMixin {
  late double _displayDeg = widget.angleDeg;
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void didUpdateWidget(covariant _SmoothedRotation oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Low-pass filter on the target angle
    final a = _displayDeg;
    final b = widget.angleDeg;
    final alpha = widget.smoothing.clamp(0.0, 1.0);
    final target = _lerpAngleDeg(a, b, 1.0 - (1.0 - alpha)); // simple low-pass

    // Animate via shortest arc
    final delta = _shortestDelta(a, target);
    _displayDeg = a + delta;

    // Kick a brief animation frame; child is wrapped by Transform.rotate below
    _ac
      ..stop()
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, child) {
        // We only need the final angle; the controller just triggers a rebuild.
        final angleRad = _displayDeg * math.pi / 180.0;
        return Transform.rotate(angle: angleRad, child: child);
      },
      child: widget.child,
    );
  }

  // Returns the shortest angular delta (degrees) to go from a -> b
  double _shortestDelta(double a, double b) {
    double d = ((b - a + 540) % 360) - 180;
    // ease small jumps (prevents micro jitter)
    if (d.abs() < 0.5) d = 0;
    return d;
  }

  // Linear interpolate on a circle (not strictly needed here, but handy)
  double _lerpAngleDeg(double a, double b, double t) {
    final d = _shortestDelta(a, b);
    return a + d * t;
  }
}
