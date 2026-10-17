import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/weather_icon.dart';
import '../../ui/widgets.dart';
import 'charts_a.dart';

/// FEEL01 Feels-like (apparent) temperature vs actual temperature.
class FeelsLikeScreen extends StatefulWidget {
  const FeelsLikeScreen({super.key, required this.location});
  final Location location;

  @override
  State<FeelsLikeScreen> createState() => _FeelsLikeScreenState();
}

class _FeelsLikeScreenState extends State<FeelsLikeScreen> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: tr(context, 'Feels like', 'Cảm giác như'),
      subtitle: widget.location.name,
      body: AsyncLoader<Json>(
        load: () => ApiClient.instance.metric('feels-like', widget.location.locationId),
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
    final actual = d(cur?['actualC']);
    final feels = d(cur?['feelsLikeC']); // never substituted by the actual temperature
    final delta = feels == null || actual == null ? null : d(cur?['deltaC']);
    final label = feels == null ? null : s(cur?['label']);
    final labelText = switch (label) {
      'warmer' => tr(context, 'Feels warmer than actual', 'Cảm giác nóng hơn thực tế'),
      'cooler' => tr(context, 'Feels cooler than actual', 'Cảm giác mát hơn thực tế'),
      'similar' => tr(context, 'Feels about the same as actual', 'Cảm giác gần bằng thực tế'),
      _ => null,
    };
    final aMin = Extremum.from(jp(json, 'summary.actual.min'));
    final aMax = Extremum.from(jp(json, 'summary.actual.max'));
    final fMin = Extremum.from(jp(json, 'summary.feelsLike.min'));
    final fMax = Extremum.from(jp(json, 'summary.feelsLike.max'));
    final coverage = coverageNote(context, jp(json, 'summary.feelsLike')) ?? coverageNote(context, jp(json, 'summary.actual'));
    final algorithm = s(cur?['algorithm']);
    final labels = hourLabels(hours, f);
    final fullLabels = hourLabels(hours, f, full: true);
    final sel = _selected != null && _selected! < hours.length ? _selected : null;
    void onSelect(int k) => setState(() => _selected = k);

    return PageList(children: [
      // ---- hero ----
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'Feels like now', 'Cảm giác như hiện tại'), style: TextStyle(color: c.textSecondary, fontSize: 16)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ValueOrReason(value: f.deg(feels), style: TextStyle(fontSize: 72, fontWeight: FontWeight.w300, height: 1.1, color: c.accent)),
                  ),
                ),
                if (delta != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.accent.withValues(alpha: .6))),
                    child: Text(f.degDelta(delta), style: TextStyle(color: c.accent, fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
              ],
            ),
            Text('${tr(context, 'Actual temperature', 'Nhiệt độ thực tế')} ${f.degU(actual)}', style: TextStyle(color: c.textPrimary, fontSize: 17)),
            if (labelText != null) Text(labelText, style: TextStyle(color: c.textSecondary, fontSize: 15)),
            if (feels == null)
              Text(tr(context, 'Feels-like value is not available from the source', 'Nguồn chưa cung cấp nhiệt độ cảm nhận'), style: TextStyle(color: c.textMuted, fontSize: 12)),
            if (algorithm != null)
              Text(tr(context, 'Apparent temperature from the forecast model', 'Nhiệt độ biểu kiến từ mô hình dự báo'), style: TextStyle(color: c.textMuted, fontSize: 12)),
          ],
        ),
      ),
      if (!sec.hasData)
        GlassCard(child: SectionNotice(status: sec.status, reason: sec.reasonCode))
      else ...[
        GlassCard(
          padding: const EdgeInsets.fromLTRB(10, 14, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sec.isStale) SectionNotice(status: sec.status, reason: sec.reasonCode, compact: true),
              ChartLegend(items: [(c.accent, tr(context, 'Feels like', 'Cảm giác như')), (c.blue, tr(context, 'Actual', 'Thực tế'))]),
              const SizedBox(height: 6),
              HourChart(
                labels: labels,
                unitLabel: f.tempUnit,
                yFormat: (v) => '${v.round()}°',
                selected: sel,
                onSelect: onSelect,
                series: [
                  ChartSeries(values: [for (final h in hours) f.temp(h.temperatureC)], color: c.blue, strokeWidth: 2),
                  ChartSeries(values: [for (final h in hours) f.temp(h.feelsLikeC)], color: c.accent, fill: true),
                ],
              ),
              if (sel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${fullLabels[sel]} · ${tr(context, 'Actual', 'Thực tế')} ${f.deg(hours[sel].temperatureC)} · '
                    '${tr(context, 'Feels like', 'Cảm giác')} ${f.deg(hours[sel].feelsLikeC)}',
                    style: TextStyle(color: c.textPrimary, fontSize: 13),
                  ),
                ),
              SourceFooter(source: sec.source, timezone: loc.timezone, stale: sec.isStale),
            ],
          ),
        ),
        TwoUp(
          a: _RangeTile(
            title: tr(context, 'Feels like', 'Cảm giác như'),
            color: c.accent,
            lowValue: f.deg(fMin?.value),
            lowTime: extremeTime(f, fMin),
            highValue: f.deg(fMax?.value),
            highTime: extremeTime(f, fMax),
          ),
          b: _RangeTile(
            title: tr(context, 'Actual', 'Thực tế'),
            color: c.blue,
            lowValue: f.deg(aMin?.value),
            lowTime: extremeTime(f, aMin),
            highValue: f.deg(aMax?.value),
            highTime: extremeTime(f, aMax),
          ),
        ),
        if (coverage != null) Text(coverage, style: TextStyle(color: c.textMuted, fontSize: 12)),
        HourTable(
          headers: [
            tr(context, 'Time', 'Giờ'),
            tr(context, 'Weather', 'Thời tiết'),
            tr(context, 'Actual', 'Thực tế'),
            tr(context, 'Feels like', 'Cảm giác'),
          ],
          flex: const [4, 3, 3, 3],
          selected: sel,
          onTap: onSelect,
          rows: [
            for (var k = 0; k < hours.length; k++)
              [
                Text(fullLabels[k], style: TextStyle(color: c.textPrimary)),
                Tooltip(
                  message: conditionLabel(context, hours[k].conditionCode, isDay: hours[k].isDay),
                  child: WeatherIcon(code: hours[k].conditionCode, isDay: hours[k].isDay, size: 26),
                ),
                Text(f.deg(hours[k].temperatureC), style: TextStyle(color: c.textPrimary)),
                Text(f.deg(hours[k].feelsLikeC), style: TextStyle(color: c.accent, fontWeight: FontWeight.w600)),
              ],
          ],
        ),
      ],
      InfoCard(
        title: tr(context, 'Why it can feel different', 'Vì sao cảm giác có thể khác'),
        body: tr(
          context,
          'Feels-like temperature combines the air temperature with other conditions. In general, high humidity can make warm air feel hotter, '
              'wind can make it feel cooler, and strong sunshine can make it feel warmer. This is a general explanation, not a diagnosis of today\'s cause.',
          'Nhiệt độ cảm nhận kết hợp nhiệt độ không khí với các điều kiện khác. Nhìn chung, độ ẩm cao có thể khiến trời nóng cảm thấy nóng hơn, '
              'gió có thể khiến cảm thấy mát hơn, và nắng mạnh có thể khiến cảm thấy ấm hơn. Đây là giải thích chung, không khẳng định nguyên nhân cụ thể hôm nay.',
        ),
      ),
    ]);
  }
}

class _RangeTile extends StatelessWidget {
  const _RangeTile({required this.title, required this.color, required this.lowValue, required this.lowTime, required this.highValue, required this.highTime});
  final String title;
  final Color color;
  final String lowValue;
  final String lowTime;
  final String highValue;
  final String highTime;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    Widget line(String label, String value, String time) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(width: 38, child: Text(label, style: TextStyle(color: c.textSecondary, fontSize: 13))),
              Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Expanded(child: Text(time, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: 13))),
            ],
          ),
        );
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          line(tr(context, 'Low', 'Thấp'), lowValue, lowTime),
          line(tr(context, 'High', 'Cao'), highValue, highTime),
        ],
      ),
    );
  }
}
