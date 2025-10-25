// lib/common/tutorial/coach_overlay.dart
import 'dart:math';
import 'package:flutter/material.dart';

class CoachStep {
  final GlobalKey key;
  final String title;
  final String description;
  final BorderRadius? radius;
  final EdgeInsets textPadding;
  CoachStep({
    required this.key,
    required this.title,
    required this.description,
    this.radius,
    this.textPadding = const EdgeInsets.symmetric(horizontal: 16),
  });
}

class CoachOverlay extends StatefulWidget {
  final List<CoachStep> steps;
  final VoidCallback onFinish;
  final Color scrimColor;
  final Duration fadeDuration;

  const CoachOverlay({
    super.key,
    required this.steps,
    required this.onFinish,
    this.scrimColor = const Color(0xCC000000),
    this.fadeDuration = const Duration(milliseconds: 220),
  });

  @override
  State<CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<CoachOverlay>
    with WidgetsBindingObserver {
  int _index = 0;
  Rect _target = Rect.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calcRect());
  }

  void _calcRect() {
    if (_index < 0 || _index >= widget.steps.length) return;
    final ctx = widget.steps[_index].key.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final offset = box.localToGlobal(Offset.zero);
    final rect = offset & box.size;

    setState(() => _target = rect.inflate(6)); // little padding glow
  }

  void _next() {
    if (_index < widget.steps.length - 1) {
      setState(() {
        _index++;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _calcRect());
    } else {
      widget.onFinish();
    }
  }

  void _back() {
    if (_index > 0) {
      setState(() => _index--);
      WidgetsBinding.instance.addPostFrameCallback((_) => _calcRect());
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];

    return AnimatedOpacity(
      opacity: 1,
      duration: widget.fadeDuration,
      child: Stack(
        children: [
          // Scrim with hole
          GestureDetector(
            onTap: _next,
            behavior: HitTestBehavior.translucent,
            child: CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _HolePainter(
                hole: _target,
                color: widget.scrimColor,
                radius: step.radius,
              ),
            ),
          ),

          // Tooltip card
          _TooltipCard(
            target: _target,
            title: step.title,
            description: step.description,
            onNext: _next,
            onBack: _back,
            canBack: _index > 0,
            isLast: _index == widget.steps.length - 1,
            padding: step.textPadding,
          ),
        ],
      ),
    );
  }
}

class _HolePainter extends CustomPainter {
  final Rect hole;
  final Color color;
  final BorderRadius? radius;

  _HolePainter({required this.hole, required this.color, this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final rrect =
        (radius == null)
            ? RRect.fromRectAndRadius(hole, const Radius.circular(10))
            : RRect.fromRectAndCorners(
              hole,
              topLeft: radius!.topLeft,
              topRight: radius!.topRight,
              bottomLeft: radius!.bottomLeft,
              bottomRight: radius!.bottomRight,
            );

    final inner = Path()..addRRect(rrect);
    final diff = Path.combine(PathOperation.difference, outer, inner);

    final paint = Paint()..color = color;
    canvas.drawPath(diff, paint);

    // Soft highlight ring
    final ring =
        Paint()
          ..color = Colors.white.withOpacity(0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
    canvas.drawRRect(rrect, ring);
  }

  @override
  bool shouldRepaint(covariant _HolePainter oldDelegate) {
    return oldDelegate.hole != hole ||
        oldDelegate.color != color ||
        oldDelegate.radius != radius;
  }
}

class _TooltipCard extends StatelessWidget {
  final Rect target;
  final String title;
  final String description;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final bool canBack;
  final bool isLast;
  final EdgeInsets padding;

  const _TooltipCard({
    required this.target,
    required this.title,
    required this.description,
    required this.onNext,
    required this.onBack,
    required this.canBack,
    required this.isLast,
    required this.padding,
  });

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final isTopSpaceEnough = target.top > screen.height * 0.33;

    // Place card above if enough space, else below.
    final cardTop =
        isTopSpaceEnough ? max(16, target.top - 120) : target.bottom + 12;

    return Positioned(
      left: 12,
      right: 12,
      top: cardTop.toDouble(),
      child: _card(context),
    );
  }

  Widget _card(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(padding.left, 14, padding.right, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(color: Color(0xFF667085), height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (canBack)
                TextButton(onPressed: onBack, child: const Text('Back')),
              const Spacer(),
              SizedBox(
                height: 40,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: const LinearGradient(
                      colors: [_purple, _purpleDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: onNext,
                    child: Text(
                      isLast ? 'Got it' : 'Next',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
