import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Hero sky illustration driven by the data's condition + isDay (not device time).
/// Drawn in code so no third-party image URL is needed; falls back to a plain
/// theme background when the "weather background" setting is off.
class SkyScene extends StatelessWidget {
  const SkyScene({super.key, required this.code, required this.isDay, required this.fadeTo});
  final String code;
  final bool? isDay;
  final Color fadeTo;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _SkyPainter(code, isDay, fadeTo), size: Size.infinite);
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.code, this.isDay, this.fadeTo);
  final String code;
  final bool? isDay;
  final Color fadeTo;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final day = isDay ?? true;
    final cloudy = const {'PARTLY_CLOUDY', 'OVERCAST', 'FOG', 'DRIZZLE', 'RAIN', 'SHOWERS', 'FREEZING_RAIN', 'SNOW', 'THUNDERSTORM'}.contains(code);
    final heavy = const {'OVERCAST', 'RAIN', 'FREEZING_RAIN', 'THUNDERSTORM', 'SNOW', 'FOG'}.contains(code);
    final sunVisible = !heavy && code != 'UNKNOWN';
    final center = Offset(w * .82, h * .28);

    // Base sky.
    final sky = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(
      sky,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: day
              ? (heavy ? const [Color(0xFF1A2A47), Color(0xFF0C1A33)] : const [Color(0xFF112A55), Color(0xFF0B1A35)])
              : const [Color(0xFF070F24), Color(0xFF0A1730)],
        ).createShader(sky),
    );

    if (sunVisible) {
      if (day) {
        canvas.drawCircle(center, w * .42, Paint()..shader = RadialGradient(colors: [const Color(0xFFFFB25C).withValues(alpha: .55), const Color(0x00FFB25C)]).createShader(Rect.fromCircle(center: center, radius: w * .42)));
        final rays = Paint()
          ..color = const Color(0x55FFC07A)
          ..strokeWidth = 2;
        for (var k = 0; k < 24; k++) {
          final a = k * math.pi / 12;
          canvas.drawLine(center + Offset(math.cos(a), math.sin(a)) * w * .1, center + Offset(math.cos(a), math.sin(a)) * w * .26, rays);
        }
        canvas.drawCircle(center, w * .085, Paint()..shader = const RadialGradient(colors: [Color(0xFFFFF0B8), Color(0xFFFFB347)]).createShader(Rect.fromCircle(center: center, radius: w * .085)));
      } else {
        canvas.drawCircle(center, w * .3, Paint()..shader = RadialGradient(colors: [const Color(0xFF9FB7FF).withValues(alpha: .25), const Color(0x009FB7FF)]).createShader(Rect.fromCircle(center: center, radius: w * .3)));
        canvas.drawCircle(center, w * .07, Paint()..color = const Color(0xFFEFF2FF));
        final rnd = math.Random(7);
        for (var k = 0; k < 40; k++) {
          canvas.drawCircle(Offset(rnd.nextDouble() * w, rnd.nextDouble() * h * .7), rnd.nextDouble() * 1.2 + .3, Paint()..color = Colors.white.withValues(alpha: .5));
        }
      }
    }

    if (cloudy || code == 'MOSTLY_CLEAR') {
      final n = heavy ? 9 : (code == 'MOSTLY_CLEAR' ? 3 : 6);
      final rnd = math.Random(code.hashCode);
      for (var k = 0; k < n; k++) {
        final c = Offset(w * (.45 + rnd.nextDouble() * .6), h * (.15 + rnd.nextDouble() * .45));
        final r = w * (.1 + rnd.nextDouble() * .12);
        final lit = day && sunVisible;
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18)
            ..shader = RadialGradient(
              center: const Alignment(.4, -.5),
              colors: lit ? const [Color(0xCCF7B98A), Color(0x99496AA8)] : const [Color(0x995F7AB0), Color(0x66233B66)],
            ).createShader(Rect.fromCircle(center: c, radius: r)),
        );
      }
    }

    // Fade into the page background.
    canvas.drawRect(
      sky,
      Paint()
        ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [fadeTo.withValues(alpha: 0), fadeTo.withValues(alpha: 0), fadeTo], stops: const [0, .6, 1]).createShader(sky),
    );
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.code != code || old.isDay != isDay || old.fadeTo != fadeTo;
}
