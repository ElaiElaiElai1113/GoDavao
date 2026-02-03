import 'package:flutter/material.dart';

class PassengerMarker extends StatelessWidget {
  const PassengerMarker({
    super.key,
    this.size = 28,
    this.ripple = true,
    this.color = const Color(0xFF2E7D32),
    this.label,
  });

  final double size;
  final bool ripple;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final pin = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.person_pin_circle, color: Colors.white, size: 18),
    );

    final body = Stack(
      alignment: Alignment.center,
      children: [
        if (ripple)
          const _Ripple(
            maxScale: 2.0,
            color: Color(0x332E7D32),
            duration: Duration(seconds: 2),
          ),
        pin,
      ],
    );

    if (label == null || label!.isEmpty) return body;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        body,
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
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

class _Ripple extends StatefulWidget {
  const _Ripple({
    required this.maxScale,
    required this.color,
    required this.duration,
  });

  final double maxScale;
  final Color color;
  final Duration duration;

  @override
  State<_Ripple> createState() => _RippleState();
}

class _RippleState extends State<_Ripple> with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat();
  late final Animation<double> _t = CurvedAnimation(
    parent: _ac,
    curve: Curves.easeOut,
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
        final s = 1.0 + (widget.maxScale - 1.0) * _t.value;
        final opacity = (1.0 - _t.value);
        return Transform.scale(
          scale: s,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: opacity),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
