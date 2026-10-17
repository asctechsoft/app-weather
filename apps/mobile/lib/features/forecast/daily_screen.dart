import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/routes.dart';
import '../../ui/theme.dart';
import '../../ui/weather_icon.dart';
import '../../ui/widgets.dart';
import '../home/home_screen.dart' show RangeBar;

/// FC02 N-day outlook (today + following days in the place's timezone).
class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key, required this.location});
  final Location location;

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  int? _horizon;

  Future<Json> _load() async {
    final json = await ApiClient.instance.daily(widget.location.locationId);
    final n = i(json['horizonDays']);
    if (mounted && n != _horizon) setState(() => _horizon = n);
    return json;
  }

  String _title(BuildContext context) {
    final n = _horizon;
    if (n == null) return tr(context, 'Daily forecast', 'Dự báo theo ngày');
    return tr(context, '$n-day outlook', 'Dự báo $n ngày');
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.location;
    final subtitle = [loc.name, loc.country].whereType<String>().join(', ');
    return DetailScaffold(
      title: _title(context),
      subtitle: subtitle.isEmpty ? null : subtitle,
      body: AsyncLoader<Json>(
        load: _load,
        builder: (context, json, reload) => _body(context, json),
      ),
    );
  }

  Widget _body(BuildContext context, Json json) {
    final c = SkyColors.of(context);
    final loc = widget.location;
    final sec = Section.parse(json['section'], DailyRecord.list);
    final days = sec.data ?? const <DailyRecord>[];
    final today = s(json['localDate']);
    final horizon = i(json['horizonDays']) ?? days.length;
    final requested = i(json['requestedDays']);

    // One shared temperature scale across all rows.
    final lows = days.map((e) => e.minC).whereType<double>();
    final highs = days.map((e) => e.maxC).whereType<double>();
    final lo = lows.isEmpty ? 0.0 : lows.reduce(math.min);
    final hi = highs.isEmpty ? 1.0 : highs.reduce(math.max);

    return PageList(children: [
      _OverviewCard(overview: m(json['overview']), horizon: horizon, requested: requested),
      if (!sec.hasData)
        GlassCard(child: SectionNotice(status: sec.status, reason: sec.reasonCode))
      else
        GlassCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            children: [
              if (sec.isStale) SectionNotice(status: sec.status, reason: sec.reasonCode, compact: true),
              for (var k = 0; k < days.length; k++) ...[
                if (k > 0) Divider(height: 1, color: c.divider),
                _DayRow(day: days[k], isToday: days[k].localDate == today, lo: lo, hi: hi, onTap: () => Routes.hourly(context, loc, date: days[k].localDate)),
              ],
            ],
          ),
        ),
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.touch_app_outlined, color: c.blue),
              const SizedBox(width: 10),
              Expanded(child: Text(tr(context, 'Tap a day for hourly details', 'Chạm một ngày để xem chi tiết theo giờ'), style: TextStyle(color: c.textPrimary))),
            ]),
            SourceFooter(source: sec.source, timezone: loc.timezone, stale: sec.isStale),
          ],
        ),
      ),
    ]);
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.overview, required this.horizon, required this.requested});
  final Json? overview;
  final int horizon;
  final int? requested;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final trend = s(overview?['trend']);
    final rainy = i(overview?['rainyDays']);
    final n = i(overview?['horizonDays']) ?? horizon;
    final String? trendText = switch (trend) {
      'warming' => tr(context, 'Warming over the next 3 days', 'Ấm dần trong 3 ngày tới'),
      'cooling' => tr(context, 'Cooling over the next 3 days', 'Mát dần trong 3 ngày tới'),
      'steady' => tr(context, 'Temperatures steady over the next 3 days', 'Nhiệt độ ổn định trong 3 ngày tới'),
      _ => null,
    };
    final parts = <String>[
      ?trendText,
      if (rainy != null)
        rainy == 0
            ? tr(context, 'No days with likely rain in the next $n days', 'Không có ngày nào nhiều khả năng mưa trong $n ngày tới')
            : tr(context, '$rainy ${rainy == 1 ? 'day' : 'days'} with likely rain in the next $n days', '$rainy ngày có khả năng mưa trong $n ngày tới'),
    ];
    final short = requested != null && horizon < requested!;
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.insights_rounded, color: c.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(tr(context, 'Overview', 'Tổng quan')),
                const SizedBox(height: 6),
                Text(
                  parts.isEmpty ? tr(context, 'Not enough data for an overview', 'Chưa đủ dữ liệu để tổng quan') : parts.join(' · '),
                  style: TextStyle(color: c.textPrimary, fontSize: 16, height: 1.35),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(context, 'Forecast guidance from a weather model; it can change.', 'Định hướng từ mô hình dự báo; có thể thay đổi.'),
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
                if (short)
                  Text(
                    tr(context, 'Only $horizon days are available from the source.', 'Nguồn chỉ có $horizon ngày dự báo.'),
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.isToday, required this.lo, required this.hi, required this.onTap});
  final DailyRecord day;
  final bool isToday;
  final double lo;
  final double hi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final fg = isToday ? c.accent : c.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: isToday
            ? BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.accent.withValues(alpha: .6)))
            : null,
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isToday ? tr(context, 'Today', 'Hôm nay') : f.weekday(day.localDate),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg),
                  ),
                  Text(f.monthDay(day.localDate), maxLines: 1, style: TextStyle(fontSize: 12, color: isToday ? c.accent : c.textSecondary)),
                ],
              ),
            ),
            WeatherIcon(code: day.conditionCode, isDay: true, size: 32),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(conditionLabel(context, day.conditionCode), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: 13)),
                  Row(children: [
                    Icon(Icons.water_drop_rounded, size: 12, color: c.blue),
                    const SizedBox(width: 2),
                    Flexible(child: Text(f.pct(day.rainProbabilityMaxPct), maxLines: 1, style: TextStyle(color: c.blue, fontSize: 12))),
                  ]),
                ],
              ),
            ),
            SizedBox(width: 34, child: Text(f.deg(day.minC), textAlign: TextAlign.right, style: TextStyle(color: c.textSecondary, fontSize: 15))),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: SizedBox(height: 8, child: RangeBar(lo: lo, hi: hi, min: day.minC, max: day.maxC)),
              ),
            ),
            SizedBox(width: 34, child: Text(f.deg(day.maxC), style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w600))),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.textMuted),
          ],
        ),
      ),
    );
  }
}
