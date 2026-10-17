import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'charts_a.dart';

/// WIND01 Wind at 10 m: speed, direction (FROM), gusts, hourly chart, Beaufort.
class WindScreen extends StatefulWidget {
  const WindScreen({super.key, required this.location});
  final Location location;

  @override
  State<WindScreen> createState() => _WindScreenState();
}

class _WindScreenState extends State<WindScreen> {
  String _emph = 'wind';
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: tr(context, 'Wind', 'Gió'),
      subtitle: widget.location.name,
      body: AsyncLoader<Json>(
        load: () => ApiClient.instance.metric('wind', widget.location.locationId),
        builder: (context, json, reload) => _body(context, json),
      ),
    );
  }

  Widget _body(BuildContext context, Json json) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final loc = widget.location;
    final sec = Section.parse(json['section'], HourlyRecord.list);
    final hours = sec.data ?? const <HourlyRecord>[];
    final cur = m(jp(json, 'summary.current'));
    final speed = d(cur?['speedMs']);
    final gust = d(cur?['gustMs']);
    final compass = s(cur?['compass']); // null when calm or direction missing
    final dirDeg = compass == null ? null : d(cur?['directionDeg']);
    final peak = Extremum.from(jp(json, 'summary.peakGust'));
    final isToday = s(json['date']) == s(json['localDate']);
    final directions = lm(jp(json, 'summary.directions'));
    final force = i(jp(json, 'summary.beaufort.force'));
    final tableVersion = s(jp(json, 'summary.beaufort.tableVersion'));
    final sel = _selected != null && _selected! < hours.length ? _selected : null;
    final labels = hourLabels(hours, f);

    return PageList(children: [
      // ---- hero ----
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.air_rounded, color: c.blue),
                        const SizedBox(width: 8),
                        Flexible(child: Text(tr(context, 'Wind speed', 'Tốc độ gió'), style: TextStyle(color: c.textSecondary, fontSize: 16))),
                      ]),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(f.windNum(speed), style: TextStyle(fontSize: 64, fontWeight: FontWeight.w700, height: 1.1, color: c.accent)),
                            const SizedBox(width: 8),
                            Text(f.windUnit, style: TextStyle(fontSize: 24, color: c.blue)),
                          ],
                        ),
                      ),
                      Text(
                        '${tr(context, 'From', 'Từ hướng')} ${compassText(context, compass)}',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.textPrimary),
                      ),
                      Text('${tr(context, 'Gusts', 'Gió giật')} ${f.windU(gust)}', style: TextStyle(fontSize: 16, color: c.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox.square(
                  dimension: 124,
                  child: CustomPaint(
                    painter: _CompassPainter(
                      deg: dirDeg,
                      ring: c.blue.withValues(alpha: .7),
                      text: c.textSecondary,
                      tick: c.textMuted,
                      letters: [tr(context, 'N', 'B'), tr(context, 'E', 'Đ'), tr(context, 'S', 'N'), tr(context, 'W', 'T')],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              dirDeg == null
                  ? tr(context, 'Calm or direction not available — no arrow shown.', 'Lặng gió hoặc chưa có hướng — không hiển thị mũi tên.')
                  : tr(context, 'The arrow points to where the wind blows from.', 'Mũi tên chỉ về phía gió thổi đến từ đó.'),
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
            Text(tr(context, 'Measured at 10 m height (model)', 'Ở độ cao 10 m (mô hình)'), style: TextStyle(color: c.textMuted, fontSize: 12)),
          ],
        ),
      ),

      // ---- chart ----
      GlassCard(
        padding: const EdgeInsets.fromLTRB(10, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PillTabs<String>(
              height: 40,
              items: [('wind', tr(context, 'Wind', 'Gió'), null), ('gusts', tr(context, 'Gusts', 'Gió giật'), null)],
              selected: _emph,
              onChanged: (v) => setState(() => _emph = v),
            ),
            const SizedBox(height: 10),
            if (!sec.hasData)
              SectionNotice(status: sec.status, reason: sec.reasonCode)
            else ...[
              if (sec.isStale) SectionNotice(status: sec.status, reason: sec.reasonCode, compact: true),
              Align(
                alignment: Alignment.centerRight,
                child: ChartLegend(items: [(c.blue, tr(context, 'Wind', 'Gió')), (c.accent, tr(context, 'Gusts', 'Gió giật'))]),
              ),
              const SizedBox(height: 4),
              HourChart(
                labels: labels,
                unitLabel: f.windUnit,
                minY: 0,
                selected: sel,
                onSelect: (k) => setState(() => _selected = k),
                series: [
                  ChartSeries(
                    values: [for (final h in hours) f.wind(h.windSpeedMs)],
                    color: c.blue,
                    fill: _emph == 'wind',
                    muted: _emph != 'wind',
                    strokeWidth: _emph == 'wind' ? 3 : 2,
                  ),
                  ChartSeries(
                    values: [for (final h in hours) f.wind(h.windGustMs)],
                    color: c.accent,
                    fill: _emph == 'gusts',
                    muted: _emph != 'gusts',
                    strokeWidth: _emph == 'gusts' ? 3 : 2,
                  ),
                ],
              ),
              if (sel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${labels[sel]} · ${tr(context, 'Wind', 'Gió')} ${f.windU(hours[sel].windSpeedMs)} · '
                    '${tr(context, 'Gusts', 'Giật')} ${f.windU(hours[sel].windGustMs)} · '
                    '${compassText(context, compassFromDeg(hours[sel].windDirectionDeg, hours[sel].windSpeedMs))}',
                    style: TextStyle(color: c.textPrimary, fontSize: 13),
                  ),
                ),
            ],
            SourceFooter(source: sec.source, timezone: loc.timezone, stale: sec.isStale),
          ],
        ),
      ),

      // ---- peak gusts + directions ----
      TwoUp(
        a: GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.bar_chart_rounded, color: c.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(isToday ? tr(context, "Today's peak gusts", 'Gió giật mạnh nhất hôm nay') : tr(context, 'Peak gusts', 'Gió giật mạnh nhất'),
                      style: TextStyle(color: c.textSecondary)),
                ),
              ]),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    ValueOrReason(value: f.windNum(peak?.value), style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: c.accent)),
                    const SizedBox(width: 6),
                    if (peak != null) Text(f.windUnit, style: TextStyle(fontSize: 18, color: c.accent)),
                  ],
                ),
              ),
              Text(
                peak == null ? tr(context, 'No gust data for this day', 'Chưa có dữ liệu gió giật cho ngày này') : '${tr(context, 'Around', 'Khoảng')} ${f.wallTime(peak.localTime)}',
                style: TextStyle(color: c.textSecondary),
              ),
            ],
          ),
        ),
        b: GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.explore_outlined, color: c.blue),
                const SizedBox(width: 8),
                Expanded(child: Text(tr(context, 'Wind direction (from)', 'Hướng gió (từ)'), style: TextStyle(color: c.textSecondary))),
              ]),
              const SizedBox(height: 10),
              if (directions.isEmpty)
                Text(Fmt.dash, style: TextStyle(color: c.textSecondary))
              else
                Row(
                  children: [
                    for (final dir in directions)
                      Expanded(
                        child: Column(
                          children: [
                            _DirArrow(deg: s(dir['compass']) == null ? null : d(dir['directionDeg']), color: c.accent),
                            const SizedBox(height: 4),
                            FittedBox(fit: BoxFit.scaleDown, child: Text(f.wallHour(s(dir['localTime'])), style: TextStyle(color: c.textSecondary, fontSize: 12))),
                            Text(compassText(context, s(dir['compass'])), style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),

      // ---- Beaufort (hidden when force is null) ----
      if (force != null && force >= 0 && force <= 12) _BeaufortCard(force: force, tableVersion: tableVersion),
    ]);
  }
}

class _DirArrow extends StatelessWidget {
  const _DirArrow({required this.deg, required this.color});
  final double? deg;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (deg == null) return SizedBox(height: 26, child: Center(child: Text(Fmt.dash, style: TextStyle(color: color))));
    // Same convention as the dial: arrow points toward the direction the wind comes from.
    return Transform.rotate(angle: deg! * math.pi / 180, child: Icon(Icons.navigation_rounded, color: color, size: 26));
  }
}

/// Compass dial; arrow points to where the wind blows FROM. No arrow when [deg] is null.
class _CompassPainter extends CustomPainter {
  _CompassPainter({required this.deg, required this.ring, required this.text, required this.tick, required this.letters});
  final double? deg;
  final Color ring;
  final Color text;
  final Color tick;
  final List<String> letters; // N E S W

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 16;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final tp = Paint()
      ..color = tick
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 8; k++) {
      final a = k * math.pi / 4 - math.pi / 2;
      final len = k.isEven ? 8.0 : 5.0;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + dir * (r - len), center + dir * (r - 2), tp);
    }
    for (var k = 0; k < 4; k++) {
      final a = k * math.pi / 2 - math.pi / 2;
      final p = center + Offset(math.cos(a), math.sin(a)) * (r + 9);
      final t = TextPainter(
        text: TextSpan(text: letters[k], style: TextStyle(color: text, fontSize: 12, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      t.paint(canvas, p - Offset(t.width / 2, t.height / 2));
    }
    final dg = deg;
    if (dg == null) return;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(dg * math.pi / 180); // 0° = north (up), clockwise
    final arrow = Path()
      ..moveTo(0, -r * .78)
      ..lineTo(r * .26, r * .3)
      ..lineTo(0, r * .12)
      ..lineTo(-r * .26, r * .3)
      ..close();
    canvas.drawPath(arrow, Paint()..shader = SkyPalette.coralGradient.createShader(Rect.fromLTWH(-r, -r, 2 * r, 2 * r)));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompassPainter old) => old.deg != deg || old.ring != ring || old.letters.join() != letters.join();
}

class _BeaufortCard extends StatelessWidget {
  const _BeaufortCard({required this.force, required this.tableVersion});
  final int force;
  final String? tableVersion;

  static const _en = [
    ('Calm', 'Smoke rises vertically.'),
    ('Light air', 'Smoke drifts; wind vanes still.'),
    ('Light breeze', 'Wind felt on the face; leaves rustle.'),
    ('Gentle breeze', 'Leaves and small twigs in constant motion.'),
    ('Moderate breeze', 'Dust and loose paper lifted; small branches move.'),
    ('Fresh breeze', 'Small trees begin to sway.'),
    ('Strong breeze', 'Large branches move; umbrellas hard to use.'),
    ('Near gale', 'Whole trees in motion; walking against the wind is hard.'),
    ('Gale', 'Twigs break off trees.'),
    ('Strong gale', 'Slight structural damage possible.'),
    ('Storm', 'Trees uprooted; considerable damage possible.'),
    ('Violent storm', 'Widespread damage possible.'),
    ('Hurricane force', 'Severe, widespread damage possible.'),
  ];

  static const _vi = [
    ('Lặng gió', 'Khói bốc thẳng lên.'),
    ('Gió rất nhẹ', 'Khói hơi lệch theo gió.'),
    ('Gió nhẹ', 'Cảm nhận gió trên mặt; lá cây xào xạc.'),
    ('Gió yếu', 'Lá và cành nhỏ lay động liên tục.'),
    ('Gió vừa', 'Bụi, giấy bay; cành nhỏ lay động.'),
    ('Gió khá mạnh', 'Cây nhỏ bắt đầu đung đưa.'),
    ('Gió mạnh', 'Cành lớn lay động; khó dùng ô.'),
    ('Gió rất mạnh', 'Cả cây rung chuyển; đi ngược gió khó khăn.'),
    ('Gió bão', 'Cành nhỏ gãy khỏi cây.'),
    ('Gió bão mạnh', 'Có thể gây hư hại nhẹ công trình.'),
    ('Bão', 'Cây có thể bật gốc; hư hại đáng kể.'),
    ('Bão rất mạnh', 'Có thể gây hư hại trên diện rộng.'),
    ('Cuồng phong', 'Có thể gây hư hại nghiêm trọng, diện rộng.'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final table = isVi(context) ? _vi : _en;
    final (name, effect) = table[force];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.waves_rounded, color: c.blue),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(context, 'Beaufort scale (now)', 'Thang Beaufort (hiện tại)'), style: TextStyle(color: c.textSecondary, fontSize: 16))),
          ]),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$force', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w700, color: c.accent)),
              const SizedBox(width: 10),
              Expanded(child: Text(name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: c.accent))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var k = 0; k <= 12; k++)
                Expanded(
                  child: Container(
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      gradient: k <= force ? SkyPalette.coralGradient : null,
                      color: k <= force ? null : c.chipBg,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var k = 0; k <= 12; k++)
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('$k',
                        style: TextStyle(fontSize: 11, color: k == force ? c.textPrimary : c.textMuted, fontWeight: k == force ? FontWeight.w700 : FontWeight.w400)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(effect, style: TextStyle(color: c.textSecondary, height: 1.4)),
          if (tableVersion != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${tr(context, 'Based on current wind speed', 'Theo tốc độ gió hiện tại')} · $tableVersion', style: TextStyle(color: c.textMuted, fontSize: 11)),
            ),
        ],
      ),
    );
  }
}
