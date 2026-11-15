import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

enum OrbMood { idle, connecting, listening, speaking, error }

/// The animated assistant orb. [level] (0..1) makes it swell with the voice.
class VioraOrb extends StatefulWidget {
  const VioraOrb({
    super.key,
    this.mood = OrbMood.idle,
    this.level = 0,
    this.size = 220,
    this.reduceMotion = false,
  });

  final OrbMood mood;
  final double level;
  final double size;
  final bool reduceMotion;

  @override
  State<VioraOrb> createState() => _VioraOrbState();
}

class _VioraOrbState extends State<VioraOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(VioraOrb old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final still = widget.reduceMotion;
    if (still && _clock.isAnimating) _clock.stop();
    if (!still && !_clock.isAnimating) _clock.repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motionOff = widget.reduceMotion || MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: widget.level),
        duration: const Duration(milliseconds: 140),
        builder: (context, level, _) => AnimatedBuilder(
          animation: _clock,
          builder: (context, _) => CustomPaint(
            size: Size.square(widget.size),
            painter: _OrbPainter(
              t: motionOff ? 0.15 : _clock.value,
              level: motionOff ? 0 : level,
              mood: widget.mood,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.t, required this.level, required this.mood});

  final double t;
  final double level;
  final OrbMood mood;

  (Color, Color, Color) get _palette => switch (mood) {
        OrbMood.listening => (VioraColors.cyan, VioraColors.violet, const Color(0xFF8CF5F0)),
        OrbMood.speaking => (VioraColors.violet, VioraColors.pink, VioraColors.violetSoft),
        OrbMood.error => (VioraColors.danger, const Color(0xFF8A2BE2), const Color(0xFFFF9DB0)),
        OrbMood.connecting => (VioraColors.violetSoft, VioraColors.cyan, Colors.white),
        OrbMood.idle => (VioraColors.violet, VioraColors.cyan, VioraColors.violetSoft),
      };

  double get _energy => switch (mood) {
        OrbMood.speaking => 0.10 + level * 0.16,
        OrbMood.listening => 0.06 + level * 0.14,
        OrbMood.connecting => 0.05,
        OrbMood.error => 0.03,
        OrbMood.idle => 0.035,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.30 * (1 + level * 0.12);
    final (a, b, hi) = _palette;
    final phase = t * 2 * math.pi;

    // Soft outer glow.
    canvas.drawCircle(
      c,
      r * 1.25,
      Paint()
        ..color = a.withValues(alpha: 0.30 + level * 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.45),
    );

    // Three wobbling translucent layers.
    for (var i = 0; i < 3; i++) {
      final path = _blob(c, r * (1.08 - i * 0.05), phase * (i.isEven ? 1 : -1.3) + i * 2.1, _energy, 3 + i);
      final layer = Color.lerp(a, b, i / 2)!;
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            center: Alignment(math.cos(phase + i) * 0.4, math.sin(phase + i) * 0.4),
            colors: [layer.withValues(alpha: 0.55), layer.withValues(alpha: 0.05)],
          ).createShader(Rect.fromCircle(center: c, radius: r * 1.2))
          ..blendMode = BlendMode.plus,
      );
    }

    // Glossy core.
    canvas.drawCircle(
      c,
      r * 0.86,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.0,
          colors: [Colors.white.withValues(alpha: 0.95), hi, a, const Color(0xFF1A1150)],
          stops: const [0.0, 0.22, 0.62, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.86)),
    );
    canvas.drawCircle(
      c,
      r * 0.86,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.5, 0.6),
          radius: 0.8,
          colors: [b.withValues(alpha: 0.75), b.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.86)),
    );

    if (mood == OrbMood.connecting) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 1.18),
        phase * 6,
        math.pi * 0.6,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.8),
      );
    }
  }

  Path _blob(Offset c, double r, double phase, double energy, int lobes) {
    final path = Path();
    const steps = 72;
    for (var s = 0; s <= steps; s++) {
      final th = s / steps * 2 * math.pi;
      final wobble = math.sin(th * lobes + phase) * energy + math.sin(th * (lobes + 2) - phase * 1.7) * energy * 0.5;
      final p = c + Offset(math.cos(th), math.sin(th)) * r * (1 + wobble);
      if (s == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t || old.level != level || old.mood != mood;
}
