import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Shared, dependency-free chart widgets for the UV / pressure / visibility /
/// air quality / astronomy / aurora screens. All painters treat `null` as a gap
/// (no bar, no point) — never as zero.

TextPainter _tp(String text, TextStyle style) =>
    TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout();

/// Vertical bar chart. `null` → no bar; `0` → thin zero bar.
class BarSeriesChart extends StatelessWidget {
  const BarSeriesChart({
    super.key,
    required this.values,
    required this.labels,
    required this.colorOf,
    this.valueText,
    this.labelEvery = 1,
    this.valueEvery,
    this.height = 170,
    this.minTop,
    this.semanticLabel,
  });

  final List<double?> values;
  final List<String> labels;
  final Color Function(double v) colorOf;
  final String Function(double v)? valueText;
  final int labelEvery;
  final int? valueEvery;
  final double height;

  /// Minimum value used as the top of the scale (e.g. 9 for Kp, 11 for UV).
  final double? minTop;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _BarPainter(
            values: values,
            labels: labels,
            colorOf: colorOf,
            valueText: valueText,
            labelEvery: math.max(1, labelEvery),
            valueEvery: math.max(1, valueEvery ?? labelEvery),
            minTop: minTop,
            textColor: c.textSecondary,
            valueColor: c.textPrimary,
            gridColor: c.divider,
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.values,
    required this.labels,
    required this.colorOf,
    required this.valueText,
    required this.labelEvery,
    required this.valueEvery,
    required this.minTop,
    required this.textColor,
    required this.valueColor,
    required this.gridColor,
  });

  final List<double?> values;
  final List<String> labels;
  final Color Function(double v) colorOf;
  final String Function(double v)? valueText;
  final int labelEvery;
  final int valueEvery;
  final double? minTop;
  final Color textColor;
  final Color valueColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    const top = 18.0;
    const bottom = 22.0;
    final baseY = size.height - bottom;
    final plotH = baseY - top;
    final present = values.whereType<double>();
    var maxV = present.isEmpty ? 1.0 : present.reduce(math.max);
    if (minTop != null) maxV = math.max(maxV, minTop!);
    if (maxV <= 0) maxV = 1;
    final colW = size.width / n;
    final barW = math.min(colW * .62, 28.0);

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), grid);

    final labelStyle = TextStyle(color: textColor, fontSize: 10.5);
    final valueStyle = TextStyle(color: valueColor, fontSize: 10.5, fontWeight: FontWeight.w600);

    for (var k = 0; k < n; k++) {
      final cx = colW * (k + .5);
      final v = values[k];
      if (v != null) {
        final h = v <= 0 ? 2.0 : math.max(2.0, v / maxV * plotH);
        final r = math.min(barW / 2, 6.0);
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - barW / 2, baseY - h, barW, h),
          topLeft: Radius.circular(v <= 0 ? 1 : r),
          topRight: Radius.circular(v <= 0 ? 1 : r),
        );
        canvas.drawRRect(rect, Paint()..color = colorOf(v));
        if (valueText != null && k % valueEvery == 0) {
          final tp = _tp(valueText!(v), valueStyle);
          final x = (cx - tp.width / 2).clamp(0.0, math.max(0.0, size.width - tp.width)).toDouble();
          tp.paint(canvas, Offset(x, baseY - h - tp.height - 2));
        }
      }
      if (k % labelEvery == 0 && k < labels.length && labels[k].isNotEmpty) {
        final tp = _tp(labels[k], labelStyle);
        final x = (cx - tp.width / 2).clamp(0.0, math.max(0.0, size.width - tp.width)).toDouble();
        tp.paint(canvas, Offset(x, baseY + 5));
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.values != values || old.labels != labels || old.textColor != textColor;
}

/// Line chart with an area fill. `null` breaks the line.
/// Values must already be converted to the display unit.
class LineSeriesChart extends StatelessWidget {
  const LineSeriesChart({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    required this.yText,
    this.labelEvery = 3,
    this.height = 180,
    this.minSpan = 1,
    this.semanticLabel,
  });

  final List<double?> values;
  final List<String> labels;
  final Color color;
  final String Function(double v) yText;
  final int labelEvery;
  final double height;

  /// Minimum visible y span so a flat series is not exaggerated.
  final double minSpan;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _LinePainter(
            values: values,
            labels: labels,
            color: color,
            yText: yText,
            labelEvery: math.max(1, labelEvery),
            minSpan: minSpan,
            textColor: c.textSecondary,
            gridColor: c.divider,
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.labels,
    required this.color,
    required this.yText,
    required this.labelEvery,
    required this.minSpan,
    required this.textColor,
    required this.gridColor,
  });

  final List<double?> values;
  final List<String> labels;
  final Color color;
  final String Function(double v) yText;
  final int labelEvery;
  final double minSpan;
  final Color textColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final present = values.whereType<double>().toList();
    if (n == 0 || present.isEmpty) return;
    var lo = present.reduce(math.min);
    var hi = present.reduce(math.max);
    if (hi - lo < minSpan) {
      final mid = (hi + lo) / 2;
      lo = mid - minSpan / 2;
      hi = mid + minSpan / 2;
    }
    final pad = (hi - lo) * .12;
    lo -= pad;
    hi += pad;

    final labelStyle = TextStyle(color: textColor, fontSize: 10.5);
    // Y labels (left gutter).
    final yLabels = [hi, (hi + lo) / 2, lo].map((v) => _tp(yText(v), labelStyle)).toList();
    final left = yLabels.map((e) => e.width).reduce(math.max) + 6;
    const top = 8.0;
    const bottom = 22.0;
    final plotW = size.width - left;
    final plotH = size.height - top - bottom;
    double yOf(double v) => top + (hi - v) / (hi - lo) * plotH;
    double xOf(int k) => left + (n == 1 ? plotW / 2 : plotW * k / (n - 1));

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final gridValues = [hi, (hi + lo) / 2, lo];
    for (var g = 0; g < 3; g++) {
      final y = yOf(gridValues[g]);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      yLabels[g].paint(canvas, Offset(0, y - yLabels[g].height / 2));
    }

    // Segments split on null.
    final segments = <List<Offset>>[];
    var cur = <Offset>[];
    for (var k = 0; k < n; k++) {
      final v = values[k];
      if (v == null) {
        if (cur.isNotEmpty) segments.add(cur);
        cur = <Offset>[];
      } else {
        cur.add(Offset(xOf(k), yOf(v)));
      }
    }
    if (cur.isNotEmpty) segments.add(cur);

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final baseY = top + plotH;
    for (final seg in segments) {
      if (seg.length == 1) {
        canvas.drawCircle(seg.first, 3, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(seg.first.dx, seg.first.dy);
      for (final p in seg.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      final area = Path.from(path)
        ..lineTo(seg.last.dx, baseY)
        ..lineTo(seg.first.dx, baseY)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: .35), color.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(left, top, plotW, plotH)),
      );
      canvas.drawPath(path, line);
    }

    for (var k = 0; k < n; k += labelEvery) {
      if (k >= labels.length || labels[k].isEmpty) continue;
      final tp = _tp(labels[k], labelStyle);
      final x = (xOf(k) - tp.width / 2).clamp(left, math.max(left, size.width - tp.width)).toDouble();
      tp.paint(canvas, Offset(x, baseY + 5));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values || old.labels != labels || old.color != color;
}

/// Horizontal gradient scale with evenly spaced tick labels and a value marker.
/// [position] is 0..1 along the scale, or null for no marker.
class GradientScale extends StatelessWidget {
  const GradientScale({super.key, required this.colors, required this.position, required this.ticks, this.markerColor});
  final List<Color> colors;
  final double? position;
  final List<String> ticks;
  final Color? markerColor;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      const marker = 20.0;
      final inner = w - marker;
      return Column(
        children: [
          SizedBox(
            height: marker,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: marker / 2),
                  child: Container(height: 10, decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), gradient: LinearGradient(colors: colors))),
                ),
                if (position != null)
                  Positioned(
                    left: position!.clamp(0.0, 1.0) * inner,
                    child: Container(
                      width: marker,
                      height: marker,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: markerColor ?? c.accent, width: 3)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 16,
            child: Stack(
              children: [
                for (var k = 0; k < ticks.length; k++)
                  Positioned(
                    left: (marker / 2 + (ticks.length == 1 ? 0 : inner * k / (ticks.length - 1)) - 14).clamp(0.0, math.max(0.0, w - 28)),
                    width: 28,
                    child: Text(ticks[k], textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: c.textSecondary)),
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

/// Two-column responsive grid (single column below 330 px), like Home's conditions grid.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minTwoColWidth = 300});
  final List<Widget> children;
  final double minTwoColWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final twoCols = box.maxWidth >= minTwoColWidth;
      final w = twoCols ? (box.maxWidth - 12) / 2 : box.maxWidth;
      return Wrap(spacing: 12, runSpacing: 12, children: [for (final t in children) SizedBox(width: w, child: t)]);
    });
  }
}

/// Informative row for a notification feature that is not available in this build.
/// Never shows a switch.
class AlertsUnavailableCard extends StatelessWidget {
  const AlertsUnavailableCard({super.key, required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notifications_off_outlined, color: c.textMuted, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.textPrimary)),
                const SizedBox(height: 4),
                Text(message, style: TextStyle(color: c.textSecondary, height: 1.35)),
                const SizedBox(height: 8),
                Pill(text: tr(context, 'Not available yet', 'Chưa hỗ trợ')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small rounded badge.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.text, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final col = color ?? c.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: col.withValues(alpha: .7)), color: col.withValues(alpha: .12)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: col)),
    );
  }
}

/// Section notice only when the section is not plainly ready.
Widget noticeFor(Section<Object?> sec, {VoidCallback? onRetry, bool compact = true}) {
  if (sec.status == 'ready' && sec.data != null) return const SizedBox.shrink();
  if (sec.status == 'ready') return SectionNotice(status: 'empty', reason: sec.reasonCode ?? 'NO_DATA', compact: compact);
  return SectionNotice(status: sec.status, reason: sec.reasonCode, onRetry: onRetry, compact: compact);
}

/// Label / value row used inside cards.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({super.key, required this.label, required this.value, this.icon, this.iconColor, this.reason});
  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: iconColor ?? c.textSecondary), const SizedBox(width: 10)],
          Expanded(child: Text(label, style: TextStyle(color: c.textSecondary, fontSize: 15))),
          const SizedBox(width: 8),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: ValueOrReason(value: value, reason: reason, style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
