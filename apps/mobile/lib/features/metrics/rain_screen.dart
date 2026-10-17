import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'charts_a.dart';

/// RAIN01 Precipitation (model estimates — never "recorded").
class RainScreen extends StatefulWidget {
  const RainScreen({super.key, required this.location});
  final Location location;

  @override
  State<RainScreen> createState() => _RainScreenState();
}

class _RainScreenState extends State<RainScreen> {
  String _window = 'today'; // today | 24h | 7d
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: tr(context, 'Precipitation', 'Lượng mưa'),
      subtitle: widget.location.name,
      body: AsyncLoader<Json>(
        loadKey: _window,
        load: () => ApiClient.instance.metric('rain', widget.location.locationId, window: _window),
        builder: (context, json, reload) => _body(context, json),
      ),
    );
  }

  Widget _body(BuildContext context, Json json) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final loc = widget.location;
    final sec = Section.parse(json['section'], HourlyRecord.list);
    final today = s(json['localDate']);
    final soFar = m(jp(json, 'summary.todaySoFar'));
    final soFarMm = d(soFar?['totalMm']);
    final soFarIncomplete = soFar?['incomplete'] == true;
    final missing = i(soFar?['hoursMissing']);
    final todayTotal = m(jp(json, 'summary.todayTotal'));
    final chance = d(jp(json, 'summary.chanceTodayMaxPct'));
    final next = m(jp(json, 'summary.nextShower'));
    final horizonH = i(jp(json, 'summary.nextShowerRule.horizonHours')) ?? 48;
    // The response may still be for the previous window while a new one loads.
    final shownWindow = s(jp(json, 'summary.window')) ?? _window;

    // ---- hero ----
    final String heroValue;
    final String heroCaption;
    if (soFar == null || soFarMm == null) {
      heroValue = Fmt.dash;
      heroCaption = reasonText(context, sec.status == 'ready' ? 'empty' : sec.status, 'NO_DATA');
    } else if (soFarMm == 0) {
      heroValue = f.precipU(0);
      heroCaption = tr(context, 'No rain estimated so far today', 'Ước tính chưa có mưa từ đầu ngày');
    } else {
      heroValue = f.precipU(soFarMm);
      heroCaption = tr(context, 'Since midnight (local time)', 'Từ 0 giờ (giờ địa phương)');
    }

    // ---- next shower ----
    String nextValue;
    String? nextCaption;
    if (next == null) {
      nextValue = tr(context, 'None expected in $horizonH h', 'Không dự kiến trong $horizonH giờ');
    } else {
      final lt = s(next['localTime']);
      final nextDate = lt == null || lt.length < 10 ? null : lt.substring(0, 10);
      String dayWord = '';
      if (nextDate != null && today != null && nextDate != today) {
        dayWord = nextDate == addLocalDays(today, 1) ? '${tr(context, 'tomorrow', 'ngày mai')} ' : '${f.weekday(nextDate)} ';
      }
      nextValue = '${tr(context, 'Expected', 'Dự kiến')} ~$dayWord${f.wallTime(lt)}';
      nextCaption = s(next['basis']) == 'amount_only'
          ? tr(context, 'Amount only, no probability', 'Chỉ có lượng mưa, không có xác suất')
          : '${f.precipU(d(next['precipitationMm']))} · ${f.pct(d(next['rainProbabilityPct']))}';
    }

    return PageList(children: [
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.water_drop_rounded, color: c.blue),
              const SizedBox(width: 8),
              Expanded(child: Text(tr(context, 'Estimated so far today (model)', 'Ước tính từ đầu ngày (mô hình)'), style: TextStyle(color: c.textSecondary, fontSize: 16))),
            ]),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: ValueOrReason(value: heroValue, style: TextStyle(fontSize: 54, fontWeight: FontWeight.w700, color: c.accent)),
            ),
            Text(heroCaption, style: TextStyle(color: c.textPrimary, fontSize: 16)),
            if (soFarIncomplete)
              Text(
                tr(context, 'Incomplete: ${missing ?? '-'} hour(s) missing', 'Chưa đủ dữ liệu: thiếu ${missing ?? '-'} giờ'),
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            Text(
              tr(context, 'Model estimate, not a rain-gauge measurement', 'Ước tính mô hình, không phải số đo trạm'),
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
      PillTabs<String>(
        items: [
          ('today', tr(context, 'Today', 'Hôm nay'), null),
          ('24h', tr(context, '24 hours', '24 giờ'), null),
          ('7d', tr(context, '7 days', '7 ngày'), null),
        ],
        selected: _window,
        onChanged: (v) => setState(() {
          _window = v;
          _selected = null;
        }),
      ),
      GlassCard(
        padding: const EdgeInsets.fromLTRB(10, 14, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (shownWindow == '7d') _weekChart(context, json, today) else _hourChart(context, sec),
            SourceFooter(source: sec.source, timezone: loc.timezone, stale: sec.isStale),
          ],
        ),
      ),
      TwoUp(
        a: StatTile(
          icon: Icons.umbrella_outlined,
          iconColor: c.blue,
          label: tr(context, 'Chance of rain', 'Khả năng mưa'),
          value: f.pct(chance),
          caption: tr(context, 'Max for the rest of today', 'Cao nhất trong phần còn lại của hôm nay'),
        ),
        b: StatTile(
          icon: Icons.water_drop_outlined,
          iconColor: c.blue,
          label: tr(context, 'Expected total today', 'Tổng dự kiến hôm nay'),
          value: f.precipU(d(todayTotal?['totalMm'])),
          caption: todayTotal?['incomplete'] == true
              ? tr(context, 'Forecast amount · incomplete data', 'Lượng dự báo · thiếu dữ liệu')
              : tr(context, 'Forecast amount', 'Lượng dự báo'),
        ),
      ),
      StatTile(
        icon: Icons.schedule_rounded,
        iconColor: c.accent,
        label: tr(context, 'Next shower', 'Cơn mưa tiếp theo'),
        value: nextValue,
        caption: nextCaption,
      ),
      InfoCard(
        title: tr(context, 'About these numbers', 'Về các con số này'),
        body: tr(
          context,
          'Chance of rain is the highest hourly probability for the rest of today. Expected total is the forecast amount for the whole local day, '
              'not a measurement. Next shower is the first hour in the next $horizonH h with at least 0.2 mm and, when available, a chance of 50% or more — '
              'an estimate, not an exact time and not an official warning.',
          'Khả năng mưa là xác suất cao nhất theo giờ trong phần còn lại của hôm nay. Tổng dự kiến là lượng mưa dự báo cho cả ngày địa phương, '
              'không phải số đo. Cơn mưa tiếp theo là giờ đầu tiên trong $horizonH giờ tới có từ 0,2 mm và (nếu có) xác suất từ 50% — '
              'chỉ là ước tính, không phải giờ chính xác hay cảnh báo chính thức.',
        ),
      ),
      GlassCard(
        child: Row(
          children: [
            Icon(Icons.notifications_off_outlined, color: c.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(context, 'Rain alerts', 'Thông báo mưa'), style: TextStyle(color: c.textMuted, fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(tr(context, 'Rain alerts are not available yet', 'Thông báo mưa chưa khả dụng'), style: TextStyle(color: c.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _hourChart(BuildContext context, Section<List<HourlyRecord>> sec) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    if (!sec.hasData) return SectionNotice(status: sec.status, reason: sec.reasonCode);
    final hours = sec.data!;
    final labels = hourLabels(hours, f);
    final sel = _selected != null && _selected! < hours.length ? _selected : null;
    final inches = f.precipUnit == 'in';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sec.isStale) SectionNotice(status: sec.status, reason: sec.reasonCode, compact: true),
        HourChart(
          labels: labels,
          unitLabel: '${f.precipUnit} ${tr(context, 'in the preceding hour', 'trong 1 giờ trước đó')}',
          minY: 0,
          yFormat: (v) => v.toStringAsFixed(inches ? 3 : (v.abs() < 1 && v != 0 ? 2 : 1)),
          selected: sel,
          onSelect: (k) => setState(() => _selected = k),
          series: [ChartSeries(values: [for (final h in hours) f.precip(h.precipitationMm)], color: c.blue, kind: SeriesKind.bar)],
        ),
        if (sel != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${f.time(hours[sel].intervalStartAt, widget.location.timezone)} – ${f.time(hours[sel].intervalEndAt, widget.location.timezone)} · '
              '${f.precipU(hours[sel].precipitationMm)} · ${tr(context, 'chance', 'khả năng')} ${f.pct(hours[sel].rainProbabilityPct)}',
              style: TextStyle(color: c.textPrimary, fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _weekChart(BuildContext context, Json json, String? today) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final week = lm(jp(json, 'summary.week'));
    if (week.isEmpty) return SectionNotice(status: 'empty', reason: 'NO_DATA');
    final inches = f.precipUnit == 'in';
    final sel = _selected != null && _selected! < week.length ? _selected : null;
    String label(Json w) {
      final ld = s(w['localDate']);
      if (ld == null) return Fmt.dash;
      return ld == today ? tr(context, 'Today', 'Nay') : f.weekday(ld);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HourChart(
          labels: [for (final w in week) label(w)],
          labelEvery: 1,
          unitLabel: '${f.precipUnit} ${tr(context, 'per day (model)', 'mỗi ngày (mô hình)')}',
          minY: 0,
          yFormat: (v) => v.toStringAsFixed(inches ? 3 : (v.abs() < 1 && v != 0 ? 2 : 1)),
          selected: sel,
          onSelect: (k) => setState(() => _selected = k),
          series: [ChartSeries(values: [for (final w in week) f.precip(d(w['totalMm']))], color: c.blue, kind: SeriesKind.bar)],
        ),
        if (sel != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${s(week[sel]['localDate']) == null ? Fmt.dash : f.dayShort(s(week[sel]['localDate'])!)} · '
              '${f.precipU(d(week[sel]['totalMm']))} · ${tr(context, 'max chance', 'khả năng cao nhất')} ${f.pct(d(week[sel]['rainProbabilityMaxPct']))}',
              style: TextStyle(color: c.textPrimary, fontSize: 13),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(tr(context, '○ = no data for that day', '○ = không có dữ liệu ngày đó'), style: TextStyle(color: c.textMuted, fontSize: 11)),
        ),
      ],
    );
  }
}
