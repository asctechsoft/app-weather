import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/weather_icon.dart';
import '../../ui/widgets.dart';
import 'charts_b.dart';

/// PRES01. Hero, gauge, chart, change and range all use sea-level pressure.
class PressureScreen extends StatelessWidget {
  const PressureScreen({super.key, required this.location});
  final Location location;

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: tr(context, 'Pressure', 'Áp suất'),
      subtitle: location.name,
      body: AsyncLoader<Json>(
        load: () => ApiClient.instance.metric('pressure', location.locationId),
        builder: (context, json, reload) => _PressureBody(json: json, location: location, reload: reload),
      ),
    );
  }
}

class _PressureBody extends StatelessWidget {
  const _PressureBody({required this.json, required this.location, required this.reload});
  final Json json;
  final Location location;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final summary = m(json['summary']);
    final section = Section.parse(json['section'], HourlyRecord.list);
    final hours = section.data ?? const <HourlyRecord>[];
    final current = m(summary?['current']);
    final slp = d(current?['seaLevelPressureHpa']);
    final surface = d(current?['surfacePressureHpa']);
    final trend = m(summary?['trend']);
    final trendCode = s(trend?['trend']);
    final delta = d(trend?['deltaHpa']);
    final trendHours = i(trend?['hours']) ?? 3;
    final range = m(summary?['range']);
    final rMin = Extremum.from(range?['min']);
    final rMax = Extremum.from(range?['max']);
    final complete = range?['complete'] != false;
    final inhg = f.units.pressure == 'inhg';

    // Gauge range: default 980–1040 hPa, expanded when data falls outside.
    final all = <double>[?slp, ?rMin?.value, ?rMax?.value, ...hours.map((h) => h.seaLevelPressureHpa).whereType<double>()];
    var lo = 980.0;
    var hi = 1040.0;
    if (all.isNotEmpty) {
      final mn = all.reduce(math.min);
      final mx = all.reduce(math.max);
      if (mn < lo) lo = (mn / 10).floor() * 10.0;
      if (mx > hi) hi = (mx / 10).ceil() * 10.0;
    }

    String deltaText() {
      final v = f.pressure(delta);
      if (v == null) return Fmt.dash;
      final str = inhg ? v.toStringAsFixed(2) : v.toStringAsFixed(1);
      return '${v > 0 ? '+' : ''}$str ${f.pressureUnit}';
    }

    final trendIcon = switch (trendCode) {
      'rising' => Icons.trending_up_rounded,
      'falling' => Icons.trending_down_rounded,
      'steady' => Icons.trending_flat_rounded,
      _ => Icons.help_outline_rounded,
    };

    final hero = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _GaugePainter(
                          lo: lo,
                          hi: hi,
                          value: slp,
                          rangeMin: rMin?.value,
                          rangeMax: rMax?.value,
                          track: c.chipBg,
                          needle: c.textPrimary,
                        ),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: ValueOrReason(value: f.pressureNum(slp), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.textPrimary)),
                          ),
                          Text(f.pressureUnit, style: TextStyle(color: c.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                    Positioned(left: 8, bottom: 0, child: Text(f.pressureNum(lo), style: TextStyle(fontSize: 10, color: c.textMuted))),
                    Positioned(right: 8, bottom: 0, child: Text(f.pressureNum(hi), style: TextStyle(fontSize: 10, color: c.textMuted))),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, 'Sea-level pressure', 'Áp suất mực nước biển'), style: TextStyle(color: c.textSecondary, fontSize: 14)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: ValueOrReason(value: f.pressureU(slp), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: c.textPrimary)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(trendIcon, color: c.accent, size: 22),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(pressureTrendText(context, trendCode, s(trend?['rate'])),
                              style: TextStyle(color: c.accent, fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr(context, 'Pressure reduced to sea level so places at different altitudes can be compared.',
                'Áp suất quy về mực nước biển để so sánh được giữa các nơi có độ cao khác nhau.'),
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
          if (current?['validAt'] != null)
            Text('${tr(context, 'Valid at', 'Hiệu lực lúc')} ${f.time(s(current?['validAt']), location.timezone)}', style: TextStyle(color: c.textMuted, fontSize: 12)),
        ],
      ),
    );

    final chart = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: tr(context, 'Today', 'Hôm nay'), trailing: f.pressureUnit),
          noticeFor(section, onRetry: reload),
          if (hours.isNotEmpty) ...[
            const SizedBox(height: 12),
            LineSeriesChart(
              values: [for (final h in hours) f.pressure(h.seaLevelPressureHpa)],
              labels: [for (final h in hours) f.wallHour(h.localTime)],
              color: c.blue,
              yText: (v) => inhg ? v.toStringAsFixed(2) : v.round().toString(),
              labelEvery: 6,
              minSpan: f.pressure(4)!,
              semanticLabel: tr(context, 'Sea-level pressure chart for today', 'Biểu đồ áp suất mực nước biển hôm nay'),
            ),
          ],
          SourceFooter(source: section.source, timezone: location.timezone, stale: section.isStale),
        ],
      ),
    );

    final tiles = ResponsiveGrid(
      children: [
        StatTile(
          icon: trendIcon,
          label: tr(context, 'Change', 'Thay đổi'),
          value: deltaText(),
          caption: tr(context, 'in $trendHours hours', 'trong $trendHours giờ'),
        ),
        StatTile(
          icon: Icons.speed_rounded,
          label: tr(context, 'Sea-level pressure', 'Áp suất mực biển'),
          value: f.pressureU(slp),
          caption: surface == null ? null : '${tr(context, 'Surface', 'Bề mặt')} ${f.pressureU(surface)}',
        ),
        StatTile(
          icon: Icons.unfold_more_rounded,
          label: tr(context, 'Today range', 'Khoảng hôm nay'),
          value: rMin == null || rMax == null ? Fmt.dash : '${f.pressureNum(rMin.value)}–${f.pressureNum(rMax.value)}',
          caption: complete ? f.pressureUnit : '${f.pressureUnit} · ${tr(context, 'partial data', 'thiếu một số giờ')}',
        ),
      ],
    );

    final strip = hours.where((h) => h.localHour % 3 == 0).toList();
    final stripCard = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: tr(context, 'Every 3 hours', 'Mỗi 3 giờ'), trailing: f.pressureUnit),
          const SizedBox(height: 10),
          if (strip.isEmpty)
            noticeFor(section.hasData ? Section(status: 'empty', reasonCode: 'NO_DATA', source: null, data: null) : section)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final h in strip)
                    SizedBox(
                      width: 66,
                      child: Column(
                        children: [
                          Text(f.wallHour(h.localTime), style: TextStyle(color: c.textSecondary, fontSize: 13)),
                          const SizedBox(height: 4),
                          WeatherIcon(code: h.conditionCode, isDay: h.isDay, size: 32),
                          const SizedBox(height: 4),
                          Text(f.pressureNum(h.seaLevelPressureHpa), style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );

    return PageList(
      children: [
        hero,
        chart,
        tiles,
        stripCard,
        InfoCard(
          title: tr(context, 'About pressure', 'Về áp suất'),
          body: tr(
            context,
            'Air pressure is the weight of the air above you. Falling pressure often comes with more clouds and wind, rising pressure with more settled weather. Pressure alone cannot predict a storm.',
            'Áp suất không khí là trọng lượng của lớp không khí phía trên. Áp suất giảm thường đi kèm nhiều mây và gió hơn, áp suất tăng thường đi kèm thời tiết ổn định hơn. Chỉ dựa vào áp suất thì không thể dự đoán bão.',
          ),
        ),
      ],
    );
  }
}

/// 270° gauge. Values in hPa; labels are drawn by the parent in the user's unit.
class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.lo, required this.hi, required this.value, required this.rangeMin, required this.rangeMax, required this.track, required this.needle});
  final double lo;
  final double hi;
  final double? value;
  final double? rangeMin;
  final double? rangeMax;
  final Color track;
  final Color needle;

  static const _start = math.pi * .75;
  static const _sweep = math.pi * 1.5;

  double _t(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );
    // Today's range band.
    if (rangeMin != null && rangeMax != null) {
      final a = _t(rangeMin!);
      final b = _t(rangeMax!);
      canvas.drawArc(
        rect,
        _start + _sweep * a,
        math.max(.02, _sweep * (b - a)),
        false,
        Paint()
          ..shader = SweepGradient(
            startAngle: _start,
            endAngle: _start + _sweep,
            colors: const [Color(0xFF6FA0FF), Color(0xFFF58A6E)],
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
    }
    // Ticks.
    final tick = Paint()
      ..color = needle.withValues(alpha: .35)
      ..strokeWidth = 1.5;
    for (var k = 0; k <= 12; k++) {
      final a = _start + _sweep * k / 12;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + dir * (r - 12), center + dir * (r - 17), tick);
    }
    if (value != null) {
      final a = _start + _sweep * _t(value!);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawCircle(center + dir * r, 8, Paint()..color = Colors.white);
      canvas.drawCircle(
        center + dir * r,
        8,
        Paint()
          ..color = const Color(0xFFF58A6E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.lo != lo || old.hi != hi || old.rangeMin != rangeMin || old.rangeMax != rangeMax;
}
