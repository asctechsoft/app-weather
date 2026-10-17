import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../metrics/charts_b.dart';

/// ASTRO01. Sun and moon live on one page; the tab scrolls to / emphasises a section.
/// Dates are calendar days at the place being viewed, never the phone's date.
class SunMoonScreen extends StatefulWidget {
  const SunMoonScreen({super.key, required this.location});
  final Location location;

  @override
  State<SunMoonScreen> createState() => _SunMoonScreenState();
}

String _ymd(DateTime t) => '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

class _SunMoonScreenState extends State<SunMoonScreen> {
  String? _date; // null → today at the place
  String _tab = 'sun';
  final _sunKey = GlobalKey();
  final _moonKey = GlobalKey();

  DateTime get _placeToday {
    final now = Fmt.local(DateTime.now().toUtc().toIso8601String(), widget.location.timezone);
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate() async {
    final today = _placeToday;
    final initial = _date == null ? today : Fmt.dateOnly(_date!);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today.subtract(const Duration(days: 1)),
      lastDate: today.add(const Duration(days: 30)),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = _ymd(picked) == _ymd(today) ? null : _ymd(picked));
  }

  void _selectTab(String t) {
    setState(() => _tab = t);
    final ctx = (t == 'sun' ? _sunKey : _moonKey).currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.location;
    return DetailScaffold(
      title: tr(context, 'Sun & moon', 'Mặt trời & mặt trăng'),
      subtitle: loc.name,
      body: AsyncLoader<Json>(
        loadKey: _date,
        load: () => ApiClient.instance.astronomy(loc.locationId, date: _date),
        builder: (context, json, reload) => _body(context, json, reload),
      ),
    );
  }

  Widget _body(BuildContext context, Json json, Future<void> Function() reload) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final loc = widget.location;
    final sun = Section.parse(json['sun'], (v) => m(v)!);
    final moon = Section.parse(json['moon'], (v) => m(v)!);
    final date = s(json['date']) ?? _date ?? _ymd(_placeToday);
    final isToday = date == _ymd(_placeToday);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.center,
            child: ActionChip(
              avatar: Icon(Icons.calendar_today_rounded, size: 18, color: c.accent),
              label: Text(isToday ? '${tr(context, 'Today', 'Hôm nay')} · ${f.dayShort(date)}' : f.dayShort(date)),
              onPressed: _pickDate,
              backgroundColor: c.chipBg,
              side: BorderSide(color: c.cardBorder),
              shape: const StadiumBorder(),
              labelStyle: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          PillTabs<String>(
            items: [
              ('sun', tr(context, 'Sun', 'Mặt trời'), Icons.wb_sunny_outlined),
              ('moon', tr(context, 'Moon', 'Mặt trăng'), Icons.nightlight_outlined),
            ],
            selected: _tab,
            onChanged: _selectTab,
          ),
          const SizedBox(height: 14),
          Container(key: _sunKey, child: _SunCard(sun: sun, location: loc, isToday: isToday, emphasised: _tab == 'sun', reload: reload)),
          const SizedBox(height: 14),
          Container(key: _moonKey, child: _MoonCard(moon: moon, location: loc, emphasised: _tab == 'moon', reload: reload)),
        ],
      ),
    );
  }
}

class _SunCard extends StatelessWidget {
  const _SunCard({required this.sun, required this.location, required this.isToday, required this.emphasised, required this.reload});
  final Section<Json> sun;
  final Location location;
  final bool isToday;
  final bool emphasised;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final tz = location.timezone;
    final dta = sun.data;
    final status = s(dta?['eventStatus']);
    final rise = s(dta?['sunriseAt']);
    final set = s(dta?['sunsetAt']);
    final noon = s(dta?['solarNoonAt']);
    final noEvent = tr(context, 'No such event on this date', 'Không có sự kiện này trong ngày');

    double? progress;
    if (isToday && rise != null && set != null) {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final a = DateTime.parse(rise).millisecondsSinceEpoch;
      final b = DateTime.parse(set).millisecondsSinceEpoch;
      if (b > a) progress = ((now - a) / (b - a)).clamp(0.0, 1.0);
    }

    final polarText = switch (status) {
      'always_up' => tr(context, 'Sun does not set', 'Mặt trời không lặn'),
      'always_down' => tr(context, 'Sun does not rise', 'Mặt trời không mọc'),
      _ => null,
    };

    Widget timeCol(String label, String? iso, CrossAxisAlignment align, Color iconColor) => Column(
          crossAxisAlignment: align,
          children: [
            Icon(Icons.wb_twilight_rounded, color: iconColor),
            Text(label, style: TextStyle(color: c.textSecondary, fontSize: 13)),
            ValueOrReason(value: f.time(iso, tz), reason: noEvent, style: TextStyle(color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.w600)),
          ],
        );

    final srcProvider = s(sun.source?.json['sunriseSunsetProviderId']);
    final algorithm = s(sun.source?.json['algorithm']);

    return GlassCard(
      borderColor: emphasised ? c.accent.withValues(alpha: .7) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: tr(context, 'Sun', 'Mặt trời'), icon: Icons.wb_sunny_outlined),
          noticeFor(sun, onRetry: reload),
          if (dta != null) ...[
            const SizedBox(height: 8),
            if (polarText != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Icon(status == 'always_up' ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded, size: 40, color: status == 'always_up' ? const Color(0xFFFFB648) : c.blue),
                    const SizedBox(width: 14),
                    Expanded(child: Text(polarText, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: c.textPrimary))),
                  ],
                ),
              )
            else ...[
              Center(
                child: Column(
                  children: [
                    Text(tr(context, 'Solar noon', 'Giữa trưa (thiên văn)'), style: TextStyle(color: c.textSecondary, fontSize: 13)),
                    ValueOrReason(value: f.time(noon, tz), reason: noEvent, style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              SizedBox(height: 90, child: CustomPaint(size: Size.infinite, painter: _SunArcPainter(progress: progress, track: c.blue, horizon: c.divider))),
              Row(
                children: [
                  Expanded(child: timeCol(tr(context, 'Sunrise', 'Mặt trời mọc'), rise, CrossAxisAlignment.start, const Color(0xFFFFB648))),
                  Expanded(child: timeCol(tr(context, 'Sunset', 'Mặt trời lặn'), set, CrossAxisAlignment.end, const Color(0xFFFF8A5B))),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Divider(color: c.divider),
            KeyValueRow(icon: Icons.hourglass_bottom_rounded, label: tr(context, 'Daylight', 'Thời gian ban ngày'), value: f.duration(d(dta['daylightSeconds']))),
            if (polarText != null) KeyValueRow(icon: Icons.light_mode_outlined, label: tr(context, 'Solar noon', 'Giữa trưa (thiên văn)'), value: f.time(noon, tz), reason: noEvent),
            const SizedBox(height: 8),
            Eyebrow(tr(context, 'Twilight', 'Chạng vạng')),
            KeyValueRow(icon: Icons.brightness_5_outlined, label: tr(context, 'Civil dawn', 'Bình minh dân dụng'), value: f.time(s(dta['civilDawnAt']), tz), reason: noEvent),
            KeyValueRow(icon: Icons.brightness_4_outlined, label: tr(context, 'Civil dusk', 'Hoàng hôn dân dụng'), value: f.time(s(dta['civilDuskAt']), tz), reason: noEvent),
          ],
          if (srcProvider != null || algorithm != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                [
                  if (srcProvider != null) '${tr(context, 'Sunrise & sunset', 'Mọc & lặn')}: ${providerName(srcProvider)}',
                  if (algorithm != null) '${tr(context, 'noon & twilight computed', 'giữa trưa & chạng vạng tính toán')} ($algorithm)',
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: c.textMuted),
              ),
            ),
          SourceFooter(source: sun.source, timezone: location.timezone, stale: sun.isStale),
        ],
      ),
    );
  }
}

/// Day arc from sunrise (left) to sunset (right); the dot is today's progress only.
class _SunArcPainter extends CustomPainter {
  _SunArcPainter({required this.progress, required this.track, required this.horizon});
  final double? progress;
  final Color track;
  final Color horizon;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(16, 8, size.width - 32, (size.height - 12) * 2);
    canvas.drawLine(Offset(0, rect.center.dy), Offset(size.width, rect.center.dy), Paint()
      ..color = horizon
      ..strokeWidth = 1.5);
    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = track.withValues(alpha: .6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    // Solar noon marker at the top.
    final top = Offset(rect.center.dx, rect.top);
    canvas.drawCircle(top, 3, Paint()..color = track);
    final p = progress;
    if (p == null) return;
    canvas.drawArc(
      rect,
      math.pi,
      math.pi * p,
      false,
      Paint()
        ..shader = SkyPalette.coralGradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    final a = math.pi + math.pi * p;
    final pos = rect.center + Offset(math.cos(a) * rect.width / 2, math.sin(a) * rect.height / 2);
    canvas.drawCircle(pos, 12, Paint()..color = const Color(0x55FFC93C));
    canvas.drawCircle(pos, 7, Paint()..color = const Color(0xFFFFC93C));
  }

  @override
  bool shouldRepaint(_SunArcPainter old) => old.progress != progress || old.track != track;
}

String _phaseLabel(BuildContext context, String? p) => switch (p) {
      'new_moon' => tr(context, 'New moon', 'Trăng mới'),
      'waxing_crescent' => tr(context, 'Waxing crescent', 'Trăng lưỡi liềm đầu tháng'),
      'first_quarter' => tr(context, 'First quarter', 'Trăng thượng huyền'),
      'waxing_gibbous' => tr(context, 'Waxing gibbous', 'Trăng khuyết đầu tháng'),
      'full_moon' => tr(context, 'Full moon', 'Trăng tròn'),
      'waning_gibbous' => tr(context, 'Waning gibbous', 'Trăng khuyết cuối tháng'),
      'last_quarter' => tr(context, 'Last quarter', 'Trăng hạ huyền'),
      'waning_crescent' => tr(context, 'Waning crescent', 'Trăng lưỡi liềm cuối tháng'),
      _ => Fmt.dash,
    };

/// Position in the lunar cycle (0 new, .25 first quarter, .5 full, .75 last quarter).
double? _cycleForName(String? p) => switch (p) {
      'new_moon' => 0,
      'waxing_crescent' => .125,
      'first_quarter' => .25,
      'waxing_gibbous' => .375,
      'full_moon' => .5,
      'waning_gibbous' => .625,
      'last_quarter' => .75,
      'waning_crescent' => .875,
      _ => null,
    };

class _MoonCard extends StatelessWidget {
  const _MoonCard({required this.moon, required this.location, required this.emphasised, required this.reload});
  final Section<Json> moon;
  final Location location;
  final bool emphasised;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final tz = location.timezone;
    final dta = moon.data;
    final phaseName = s(dta?['phaseName']);
    final phase = d(dta?['phase']) ?? _cycleForName(phaseName);
    final riseSet = s(dta?['riseSetStatus']);
    final rise = s(dta?['moonriseAt']);
    final set = s(dta?['moonsetAt']);
    final upcoming = lm(dta?['upcomingPhases']).take(4).toList();

    String riseText() {
      if (rise != null) return f.time(rise, tz);
      if (riseSet == 'always_up') return tr(context, 'Moon stays up', 'Trăng ở trên trời cả ngày');
      if (riseSet == 'always_down') return tr(context, 'Moon stays down', 'Trăng dưới chân trời cả ngày');
      return tr(context, 'No moonrise this day', 'Không có trăng mọc ngày này');
    }

    String setText() {
      if (set != null) return f.time(set, tz);
      if (riseSet == 'always_up') return tr(context, 'Moon stays up', 'Trăng ở trên trời cả ngày');
      if (riseSet == 'always_down') return tr(context, 'Moon stays down', 'Trăng dưới chân trời cả ngày');
      return tr(context, 'No moonset this day', 'Không có trăng lặn ngày này');
    }

    return GlassCard(
      borderColor: emphasised ? c.accent.withValues(alpha: .7) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: tr(context, 'Moon', 'Mặt trăng'), icon: Icons.nightlight_outlined),
          noticeFor(moon, onRetry: reload),
          if (dta != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                MoonDisc(phase: phase, size: 96),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_phaseLabel(context, phaseName), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.textPrimary)),
                      const SizedBox(height: 4),
                      Text('${tr(context, 'Illumination', 'Độ chiếu sáng')} ${f.pct(d(dta['illuminationPct']))}', style: TextStyle(color: c.textPrimary, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                        tr(context, 'Share of the disc lit by the sun, not the chance of seeing the moon.', 'Tỷ lệ phần đĩa được chiếu sáng, không phải khả năng nhìn thấy trăng.'),
                        style: TextStyle(color: c.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            KeyValueRow(icon: Icons.arrow_upward_rounded, label: tr(context, 'Moonrise', 'Trăng mọc'), value: riseText()),
            KeyValueRow(icon: Icons.arrow_downward_rounded, label: tr(context, 'Moonset', 'Trăng lặn'), value: setText()),
            if (upcoming.isNotEmpty) ...[
              const SizedBox(height: 10),
              Eyebrow(tr(context, 'Upcoming phases', 'Các pha sắp tới')),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final u in upcoming)
                    Expanded(
                      child: Column(
                        children: [
                          MoonDisc(phase: _cycleForName(s(u['phase'])), size: 36),
                          const SizedBox(height: 6),
                          Text(_phaseLabel(context, s(u['phase'])), textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 12, color: c.textPrimary)),
                          Text(s(u['localDate']) == null ? Fmt.dash : f.monthDay(s(u['localDate'])!), style: TextStyle(fontSize: 12, color: c.textSecondary)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
          SourceFooter(source: moon.source, timezone: location.timezone, stale: moon.isStale),
        ],
      ),
    );
  }
}

/// Painted moon disc for a cycle position (0 new → .5 full → 1 new). Lit side as seen
/// from the northern hemisphere. Null → plain dark disc.
class MoonDisc extends StatelessWidget {
  const MoonDisc({super.key, required this.phase, this.size = 64});
  final double? phase;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size, child: CustomPaint(painter: _MoonPainter(phase)));
}

class _MoonPainter extends CustomPainter {
  _MoonPainter(this.phase);
  final double? phase;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 * .9;
    final center = size.center(Offset.zero);
    final disc = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(center, r * 1.08, Paint()..color = const Color(0x22FFF3C4));
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFF2A3656));
    final p0 = phase;
    if (p0 == null) return;
    final p = p0 - p0.floorToDouble();
    final t = math.cos(2 * math.pi * p); // 1 new, -1 full
    final ell = Rect.fromCenter(center: center, width: math.max(.01, 2 * r * t.abs()), height: 2 * r);
    final waxing = p < .5;
    final path = Path();
    if (waxing) {
      path.arcTo(disc, -math.pi / 2, math.pi, true); // top → right → bottom
      path.arcTo(ell, math.pi / 2, t > 0 ? -math.pi : math.pi, false); // back to top
    } else {
      path.arcTo(disc, math.pi / 2, math.pi, true); // bottom → left → top
      path.arcTo(ell, -math.pi / 2, t > 0 ? -math.pi : math.pi, false); // back to bottom
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..shader = const RadialGradient(colors: [Color(0xFFFFF6D8), Color(0xFFE6CF8A)]).createShader(disc),
    );
  }

  @override
  bool shouldRepaint(_MoonPainter old) => old.phase != phase;
}
