import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Shared chart + table helpers for the forecast / wind / rain / humidity / feels-like screens.
/// All values handed to the chart must already be converted to display units (via [Fmt]).
/// `null` values are never joined: lines break, bars show a small hollow gap marker.

enum SeriesKind { line, bar }

class ChartSeries {
  const ChartSeries({
    required this.values,
    required this.color,
    this.label,
    this.kind = SeriesKind.line,
    this.fill = false,
    this.strokeWidth = 2.5,
    this.muted = false,
  });

  final List<double?> values;
  final Color color;
  final String? label;
  final SeriesKind kind;
  final bool fill;
  final double strokeWidth;

  /// De-emphasized series (drawn semi-transparent).
  final bool muted;
}

/// Hour-by-hour chart drawn with a CustomPainter (one slot per record).
class HourChart extends StatelessWidget {
  const HourChart({
    super.key,
    required this.labels,
    required this.series,
    this.minY,
    this.maxY,
    this.yFormat,
    this.height = 190,
    this.selected,
    this.onSelect,
    this.unitLabel,
    this.labelEvery,
    this.semanticLabel,
  });

  /// X axis labels, one per slot (location local time).
  final List<String> labels;
  final List<ChartSeries> series;
  final double? minY;
  final double? maxY;
  final String Function(double v)? yFormat;
  final double height;
  final int? selected;
  final ValueChanged<int>? onSelect;
  final String? unitLabel;
  final int? labelEvery;
  final String? semanticLabel;

  static const double _left = 40;
  static const double _right = 8;

  (double, double) _range() {
    final vals = <double>[for (final s in series) ...s.values.whereType<double>()];
    final hasBars = series.any((s) => s.kind == SeriesKind.bar);
    var lo = minY ?? (vals.isEmpty ? 0.0 : vals.reduce(math.min));
    var hi = maxY ?? (vals.isEmpty ? 1.0 : vals.reduce(math.max));
    if (hasBars && minY == null) lo = math.min(lo, 0.0);
    if (hi - lo < 1e-6) hi = lo + 1;
    final span = hi - lo;
    if (minY == null && !hasBars) lo -= span * .15;
    if (maxY == null) hi += span * .15;
    return (lo, hi);
  }

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final (lo, hi) = _range();
    final span = hi - lo;
    final String Function(double) fmt = yFormat ?? ((double v) => span >= 4 ? v.round().toString() : v.toStringAsFixed(1));
    final n = labels.length;
    final every = labelEvery ?? math.max(1, (n / 6).ceil());
    return Semantics(
      label: semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (unitLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(unitLabel!, style: TextStyle(color: c.textSecondary, fontSize: 12)),
            ),
          LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            int indexAt(double dx) {
              if (n == 0) return 0;
              final slot = (w - _left - _right) / n;
              return ((dx - _left) / slot).floor().clamp(0, n - 1).toInt();
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: onSelect == null || n == 0 ? null : (d) => onSelect!(indexAt(d.localPosition.dx)),
              child: CustomPaint(
                size: Size(w, height),
                painter: _HourChartPainter(
                  series: series,
                  labels: labels,
                  lo: lo,
                  hi: hi,
                  yFormat: fmt,
                  selected: selected,
                  textColor: c.textSecondary,
                  gridColor: c.divider,
                  every: every,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _HourChartPainter extends CustomPainter {
  _HourChartPainter({
    required this.series,
    required this.labels,
    required this.lo,
    required this.hi,
    required this.yFormat,
    required this.selected,
    required this.textColor,
    required this.gridColor,
    required this.every,
  });

  final List<ChartSeries> series;
  final List<String> labels;
  final double lo;
  final double hi;
  final String Function(double v) yFormat;
  final int? selected;
  final Color textColor;
  final Color gridColor;
  final int every;

  static const double left = HourChart._left;
  static const double right = HourChart._right;
  static const double top = 10;
  static const double bottom = 22;

  void _text(Canvas canvas, String t, Offset at, TextStyle style, {double ax = .5, double ay = .5, double? maxX}) {
    final tp = TextPainter(text: TextSpan(text: t, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
    var dx = at.dx - tp.width * ax;
    if (maxX != null) dx = dx.clamp(0.0, math.max(0.0, maxX - tp.width)).toDouble();
    tp.paint(canvas, Offset(dx, at.dy - tp.height * ay));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n == 0) return;
    final plotW = size.width - left - right;
    final plotH = size.height - top - bottom;
    final slot = plotW / n;
    double x(int i) => left + slot * (i + .5);
    double y(double v) => top + plotH - ((v - lo) / (hi - lo)).clamp(0.0, 1.0).toDouble() * plotH;
    final style = TextStyle(color: textColor, fontSize: 11);

    // Grid + Y labels.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var k = 0; k <= 4; k++) {
      final v = lo + (hi - lo) * k / 4;
      final yy = y(v);
      canvas.drawLine(Offset(left, yy), Offset(size.width - right, yy), grid);
      _text(canvas, yFormat(v), Offset(left - 6, yy), style, ax: 1);
    }

    // X labels.
    for (var i = 0; i < n; i += every) {
      _text(canvas, labels[i], Offset(x(i), size.height - bottom + 6), style, ay: 0, maxX: size.width);
    }

    // Selected marker.
    final sel = selected;
    if (sel != null && sel >= 0 && sel < n) {
      canvas.drawLine(
        Offset(x(sel), top),
        Offset(x(sel), top + plotH),
        Paint()
          ..color = textColor.withValues(alpha: .6)
          ..strokeWidth = 1,
      );
    }

    // Bars (grouped side by side when several bar series).
    final bars = series.where((s) => s.kind == SeriesKind.bar).toList();
    final base = y(math.max(lo, math.min(0.0, hi)));
    final groupW = slot * .7;
    for (var b = 0; b < bars.length; b++) {
      final s = bars[b];
      final bw = groupW / bars.length;
      for (var i = 0; i < n; i++) {
        final v = i < s.values.length ? s.values[i] : null;
        final bx = x(i) - groupW / 2 + bw * b;
        if (v == null) {
          // Gap marker: missing value is not zero.
          canvas.drawCircle(
            Offset(bx + bw / 2, base - 4),
            2.2,
            Paint()
              ..color = textColor.withValues(alpha: .6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
          continue;
        }
        final vy = y(v);
        final alpha = s.muted ? .45 : (sel == null || sel == i ? .95 : .7);
        final paint = Paint()..color = s.color.withValues(alpha: alpha);
        final l = bx + math.min(1.0, bw * .1);
        final r = bx + bw - math.min(1.0, bw * .1);
        if ((base - vy).abs() < 1.5) {
          // A true zero: thin baseline tick.
          canvas.drawRect(Rect.fromLTRB(l, base - 1.5, r, base), paint);
        } else {
          final rect = Rect.fromLTRB(l, math.min(vy, base), r, math.max(vy, base));
          canvas.drawRRect(RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(3), topRight: const Radius.circular(3)), paint);
        }
      }
    }

    // Lines (break at nulls).
    for (final s in series.where((s) => s.kind == SeriesKind.line)) {
      final segs = <List<Offset>>[];
      var cur = <Offset>[];
      for (var i = 0; i < n; i++) {
        final v = i < s.values.length ? s.values[i] : null;
        if (v == null) {
          if (cur.isNotEmpty) segs.add(cur);
          cur = <Offset>[];
        } else {
          cur.add(Offset(x(i), y(v)));
        }
      }
      if (cur.isNotEmpty) segs.add(cur);
      final color = s.color.withValues(alpha: s.muted ? .5 : 1);
      for (final seg in segs) {
        if (s.fill && seg.length > 1) {
          final area = Path()..moveTo(seg.first.dx, top + plotH);
          for (final p in seg) {
            area.lineTo(p.dx, p.dy);
          }
          area
            ..lineTo(seg.last.dx, top + plotH)
            ..close();
          canvas.drawPath(
            area,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [s.color.withValues(alpha: s.muted ? .15 : .35), s.color.withValues(alpha: 0)],
              ).createShader(Rect.fromLTWH(0, top, size.width, plotH)),
          );
        }
        if (seg.length > 1) {
          final path = Path()..moveTo(seg.first.dx, seg.first.dy);
          for (final p in seg.skip(1)) {
            path.lineTo(p.dx, p.dy);
          }
          canvas.drawPath(
            path,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = s.strokeWidth
              ..strokeJoin = StrokeJoin.round
              ..strokeCap = StrokeCap.round,
          );
        } else {
          // Isolated point between two gaps.
          canvas.drawCircle(seg.first, 3, Paint()..color = color);
        }
      }
      if (sel != null && sel >= 0 && sel < n && sel < s.values.length && s.values[sel] != null) {
        final p = Offset(x(sel), y(s.values[sel]!));
        canvas.drawCircle(p, 5.5, Paint()..color = Colors.white);
        canvas.drawCircle(p, 4, Paint()..color = s.color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Colored dot legend: "● Wind  ● Gusts".
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});
  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final (color, label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: c.textSecondary, fontSize: 13)),
            ],
          ),
      ],
    );
  }
}

/// Simple glass table: header row + tappable rows. Cells scale down instead of overflowing.
class HourTable extends StatelessWidget {
  const HourTable({super.key, required this.headers, required this.rows, this.flex, this.onTap, this.selected});

  final List<String> headers;
  final List<List<Widget>> rows;
  final List<int>? flex;
  final ValueChanged<int>? onTap;
  final int? selected;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    Widget cell(int k, Widget child) => Expanded(
          flex: flex != null && k < flex!.length ? flex![k] : 1,
          child: Align(
            alignment: k == 0 ? Alignment.centerLeft : Alignment.center,
            child: FittedBox(fit: BoxFit.scaleDown, child: child),
          ),
        );
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                for (var k = 0; k < headers.length; k++)
                  cell(k, Text(headers[k], style: TextStyle(color: c.textSecondary, fontSize: 13))),
              ],
            ),
          ),
          for (var r = 0; r < rows.length; r++) ...[
            Divider(height: 1, color: c.divider),
            InkWell(
              onTap: onTap == null ? null : () => onTap!(r),
              child: Container(
                color: selected == r ? c.accentSoft : null,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [for (var k = 0; k < rows[r].length; k++) cell(k, rows[r][k])]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "UTC+7", "UTC-3:30".
String utcOffsetLabel(int seconds) {
  final sign = seconds < 0 ? '-' : '+';
  final a = seconds.abs();
  final h = a ~/ 3600;
  final mm = (a % 3600) ~/ 60;
  return 'UTC$sign$h${mm == 0 ? '' : ':${mm.toString().padLeft(2, '0')}'}';
}

/// Local-time labels for hourly records. When two records share the same wall-clock
/// label (DST fall-back), the UTC offset is appended so both rows stay distinct.
List<String> hourLabels(List<HourlyRecord> records, Fmt f, {bool full = false}) {
  final counts = <String, int>{};
  for (final r in records) {
    counts[r.localTime] = (counts[r.localTime] ?? 0) + 1;
  }
  return [
    for (final r in records)
      (full ? f.wallTime(r.localTime) : f.wallHour(r.localTime)) + ((counts[r.localTime] ?? 0) > 1 ? ' (${utcOffsetLabel(r.utcOffsetSeconds)})' : ''),
  ];
}

const _compass16 = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];

/// 16-point compass for the direction the wind comes FROM. Null or calm (< 0.5 m/s) → null.
/// 0 and 360 both map to N.
String? compassFromDeg(double? deg, double? speedMs) {
  if (deg == null) return null;
  if (speedMs != null && speedMs < 0.5) return null;
  final n = ((deg % 360) + 360) % 360;
  return _compass16[(n / 22.5).round() % 16];
}

/// "Based on 18 of 24 hours with data" when a min/max summary is incomplete; null otherwise.
String? coverageNote(BuildContext context, Object? stats) {
  final j = m(stats);
  if (j == null || j['complete'] == true) return null;
  final valid = i(j['validCount']);
  final total = i(j['totalCount']);
  if (valid == null || total == null || total == 0) return null;
  return tr(context, 'Based on $valid of $total hours with data', 'Tính từ $valid/$total giờ có dữ liệu');
}

/// Local wall time of an extremum, or "-".
String extremeTime(Fmt f, Extremum? e) => e == null ? Fmt.dash : f.wallTime(e.localTime);

/// "YYYY-MM-DD" + days (calendar arithmetic on the location's local date).
String addLocalDays(String localDate, int days) {
  final t = DateTime.utc(int.parse(localDate.substring(0, 4)), int.parse(localDate.substring(5, 7)), int.parse(localDate.substring(8, 10)) + days);
  return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// Small label/value line for bottom sheets and cards.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({super.key, required this.label, required this.value, this.sub});
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(label, style: TextStyle(color: c.textSecondary))),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ValueOrReason(value: value, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
                if (sub != null) Text(sub!, textAlign: TextAlign.right, style: TextStyle(color: c.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two widgets side by side on normal phones, stacked below 330 px.
class TwoUp extends StatelessWidget {
  const TwoUp({super.key, required this.a, required this.b});
  final Widget a;
  final Widget b;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 330) return Column(children: [a, const SizedBox(height: 12), b]);
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
        ),
      );
    });
  }
}
