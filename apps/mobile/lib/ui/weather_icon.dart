import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Vector weather icon keyed by internal condition code + isDay (never device time).
/// UNKNOWN renders a neutral cloud with a question mark — never a sun.
class WeatherIcon extends StatelessWidget {
  const WeatherIcon({super.key, required this.code, this.isDay, this.size = 40});

  final String code;
  final bool? isDay;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: code.toLowerCase().replaceAll('_', ' '),
      child: SizedBox.square(dimension: size, child: CustomPaint(painter: _WeatherPainter(code, isDay ?? true))),
    );
  }
}

class _WeatherPainter extends CustomPainter {
  _WeatherPainter(this.code, this.isDay);
  final String code;
  final bool isDay;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    switch (code) {
      case 'CLEAR':
        isDay ? _sun(canvas, Offset(s * .5, s * .5), s * .24, s) : _moon(canvas, Offset(s * .5, s * .5), s * .26);
      case 'MOSTLY_CLEAR':
        isDay ? _sun(canvas, Offset(s * .42, s * .42), s * .2, s) : _moon(canvas, Offset(s * .42, s * .42), s * .2);
        _cloud(canvas, Rect.fromLTWH(s * .38, s * .55, s * .52, s * .3), const [Color(0xFFFFFFFF), Color(0xFFB9CCF2)]);
      case 'PARTLY_CLOUDY':
        isDay ? _sun(canvas, Offset(s * .38, s * .36), s * .19, s) : _moon(canvas, Offset(s * .38, s * .36), s * .18);
        _cloud(canvas, Rect.fromLTWH(s * .22, s * .45, s * .68, s * .38), const [Color(0xFFFFFFFF), Color(0xFFAFC4F0)]);
      case 'OVERCAST':
        _cloud(canvas, Rect.fromLTWH(s * .3, s * .22, s * .6, s * .34), const [Color(0xFFC9D5EE), Color(0xFF8394BC)]);
        _cloud(canvas, Rect.fromLTWH(s * .1, s * .4, s * .72, s * .4), const [Color(0xFFF2F6FF), Color(0xFFA5B7DF)]);
      case 'FOG':
        _cloud(canvas, Rect.fromLTWH(s * .16, s * .18, s * .68, s * .38), const [Color(0xFFE8EEFA), Color(0xFFA5B7DF)]);
        final p = Paint()
          ..color = const Color(0xFFB7C6E8)
          ..strokeWidth = s * .05
          ..strokeCap = StrokeCap.round;
        for (var k = 0; k < 3; k++) {
          final y = s * (.64 + k * .1);
          canvas.drawLine(Offset(s * (.2 + k * .05), y), Offset(s * (.8 - k * .03), y), p);
        }
      case 'DRIZZLE':
      case 'RAIN':
      case 'SHOWERS':
      case 'FREEZING_RAIN':
        if (code == 'SHOWERS') isDay ? _sun(canvas, Offset(s * .32, s * .3), s * .15, s) : _moon(canvas, Offset(s * .32, s * .3), s * .14);
        _cloud(canvas, Rect.fromLTWH(s * .14, s * .16, s * .72, s * .42), const [Color(0xFFE6EDFB), Color(0xFF8EA4D6)]);
        _drops(canvas, s, code == 'DRIZZLE' ? 2 : 3, code == 'FREEZING_RAIN' ? const Color(0xFFBFE6FF) : const Color(0xFF5AB4FF));
        if (code == 'FREEZING_RAIN') _flakes(canvas, s, const [Offset(.7, .86)]);
      case 'SNOW':
        _cloud(canvas, Rect.fromLTWH(s * .14, s * .16, s * .72, s * .42), const [Color(0xFFF2F6FF), Color(0xFFA8BAE2)]);
        _flakes(canvas, s, const [Offset(.32, .74), Offset(.52, .84), Offset(.7, .72)]);
      case 'THUNDERSTORM':
        _cloud(canvas, Rect.fromLTWH(s * .14, s * .14, s * .72, s * .42), const [Color(0xFFB9C7E6), Color(0xFF5E70A0)]);
        final bolt = Path()
          ..moveTo(s * .52, s * .5)
          ..lineTo(s * .4, s * .72)
          ..lineTo(s * .5, s * .72)
          ..lineTo(s * .44, s * .92)
          ..lineTo(s * .64, s * .64)
          ..lineTo(s * .54, s * .64)
          ..lineTo(s * .6, s * .5)
          ..close();
        canvas.drawPath(bolt, Paint()..color = const Color(0xFFFFC93C));
        _drops(canvas, s, 2, const Color(0xFF5AB4FF), offsetX: .18);
      default:
        _cloud(canvas, Rect.fromLTWH(s * .14, s * .25, s * .72, s * .45), const [Color(0xFFB5C0D8), Color(0xFF6E7C9E)]);
        final tp = TextPainter(
          text: TextSpan(text: '?', style: TextStyle(color: const Color(0xFF1B2B4D), fontSize: s * .3, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(s * .5 - tp.width / 2, s * .48 - tp.height / 2));
    }
  }

  void _sun(Canvas canvas, Offset c, double r, double s) {
    final rays = Paint()
      ..color = const Color(0xFFFFB648)
      ..strokeWidth = s * .045
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 8; k++) {
      final a = k * math.pi / 4;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (r * 1.35), c + Offset(math.cos(a), math.sin(a)) * (r * 1.75), rays);
    }
    canvas.drawCircle(c, r * 1.15, Paint()..color = const Color(0x33FFB648));
    canvas.drawCircle(
      c,
      r,
      Paint()..shader = const RadialGradient(colors: [Color(0xFFFFE07A), Color(0xFFFF9F2E)]).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  void _moon(Canvas canvas, Offset c, double r) {
    final path = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: c, radius: r)),
      Path()..addOval(Rect.fromCircle(center: c + Offset(r * .55, -r * .35), radius: r * .85)),
    );
    canvas.drawPath(path, Paint()..shader = const LinearGradient(colors: [Color(0xFFFFF3C4), Color(0xFFE4C66E)]).createShader(Rect.fromCircle(center: c, radius: r)));
  }

  void _cloud(Canvas canvas, Rect r, List<Color> colors) {
    final h = r.height;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r.left, r.top + h * .45, r.width, h * .55), Radius.circular(h * .3)))
      ..addOval(Rect.fromCircle(center: Offset(r.left + r.width * .32, r.top + h * .55), radius: h * .34))
      ..addOval(Rect.fromCircle(center: Offset(r.left + r.width * .58, r.top + h * .42), radius: h * .42))
      ..addOval(Rect.fromCircle(center: Offset(r.left + r.width * .8, r.top + h * .62), radius: h * .28));
    canvas.drawPath(path.shift(const Offset(0, 1.5)), Paint()..color = const Color(0x33000000));
    canvas.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(r));
  }

  void _drops(Canvas canvas, double s, int n, Color color, {double offsetX = 0}) {
    final p = Paint()
      ..color = color
      ..strokeWidth = s * .05
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < n; k++) {
      final x = s * (.32 + offsetX + k * .17);
      canvas.drawLine(Offset(x, s * .68), Offset(x - s * .05, s * .82), p);
    }
  }

  void _flakes(Canvas canvas, double s, List<Offset> at) {
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = s * .03
      ..strokeCap = StrokeCap.round;
    for (final o in at) {
      final c = Offset(o.dx * s, o.dy * s);
      for (var k = 0; k < 3; k++) {
        final a = k * math.pi / 3;
        final d = Offset(math.cos(a), math.sin(a)) * s * .05;
        canvas.drawLine(c - d, c + d, p);
      }
    }
  }

  @override
  bool shouldRepaint(_WeatherPainter old) => old.code != code || old.isDay != isDay;
}
