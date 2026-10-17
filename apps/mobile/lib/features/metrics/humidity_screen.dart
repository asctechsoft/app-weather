import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/weather_icon.dart';
import '../../ui/widgets.dart';
import 'charts_a.dart';

/// HUM01 Relative humidity + dew point for the place's local day.
class HumidityScreen extends StatefulWidget {
  const HumidityScreen({super.key, required this.location});
  final Location location;

  @override
  State<HumidityScreen> createState() => _HumidityScreenState();
}

class _HumidityScreenState extends State<HumidityScreen> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: tr(context, 'Humidity', 'Độ ẩm'),
      subtitle: widget.location.name,
      body: AsyncLoader<Json>(
        load: () => ApiClient.instance.metric('humidity', widget.location.locationId),
        builder: (context, json, reload) => _body(context, json),
      ),
    );
  }

  /// Product labels from the server thresholds (not a comfort standard).
  static String? _labelCode(double? pct, Json? t) {
    if (pct == null) return null;
    final low = d(t?['lowBelow']) ?? 30;
    final moderate = d(t?['moderateBelow']) ?? 60;
    final high = d(t?['highUpTo']) ?? 80;
    if (pct < low) return 'low';
    if (pct < moderate) return 'moderate';
    if (pct <= high) return 'high';
    return 'very_high';
  }

  String _shortLabel(BuildContext context, String? code) => switch (code) {
        'low' => tr(context, 'Low', 'Thấp'),
        'moderate' => tr(context, 'Moderate', 'Trung bình'),
        'high' => tr(context, 'High', 'Cao'),
        'very_high' => tr(context, 'Very high', 'Rất cao'),
        _ => Fmt.dash,
      };

  Widget _body(BuildContext context, Json json) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final loc = widget.location;
    final sec = Section.parse(json['section'], HourlyRecord.list);
    final hours = sec.data ?? const <HourlyRecord>[];
    final cur = m(jp(json, 'summary.current'));
    final thresholds = m(jp(json, 'summary.thresholds'));
    final hMax = Extremum.from(jp(json, 'summary.humidity.max'));
    final hMin = Extremum.from(jp(json, 'summary.humidity.min'));
    final coverage = coverageNote(context, jp(json, 'summary.humidity'));
    final date = s(json['date']);
    final labels = hourLabels(hours, f);
    final fullLabels = hourLabels(hours, f, full: true);
    final sel = _selected != null && _selected! < hours.length ? _selected : null;
    final hasDew = hours.any((h) => h.dewPointC != null);
    void onSelect(int k) => setState(() => _selected = k);

    return PageList(children: [
      // ---- hero ----
      GlassCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(context, 'Relative humidity now', 'Độ ẩm tương đối hiện tại'), style: TextStyle(color: c.textSecondary, fontSize: 16)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ValueOrReason(value: f.pct(d(cur?['humidityPct'])), style: TextStyle(fontSize: 60, fontWeight: FontWeight.w700, height: 1.1, color: c.accent)),
                  ),
                  Text(humidityLabelText(context, s(cur?['label'])), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.textPrimary)),
                  const SizedBox(height: 4),
                  Text('${tr(context, 'Dew point', 'Điểm sương')} ${f.degU(d(cur?['dewPointC']))}', style: TextStyle(color: c.textSecondary, fontSize: 16)),
                ],
              ),
            ),
            Icon(Icons.water_drop_rounded, size: 72, color: c.blue.withValues(alpha: .8)),
          ],
        ),
      ),
      InfoCard(
        title: tr(context, 'Humidity and dew point', 'Độ ẩm và điểm sương'),
        body: tr(
          context,
          'Relative humidity is how much water vapour the air holds compared with the most it could hold at the current temperature. '
              'Dew point is the temperature at which the air would become saturated; a higher dew point usually feels more humid. '
              'Labels: below 30% low, 30–59% moderate, 60–80% high, above 80% very high (app description, not a health standard).',
          'Độ ẩm tương đối là lượng hơi nước trong không khí so với mức tối đa không khí có thể chứa ở nhiệt độ hiện tại. '
              'Điểm sương là nhiệt độ mà không khí sẽ bão hòa; điểm sương càng cao thường càng cảm thấy oi ẩm. '
              'Nhãn: dưới 30% thấp, 30–59% trung bình, 60–80% cao, trên 80% rất cao (mô tả của ứng dụng, không phải tiêu chuẩn sức khỏe).',
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
              Text(
                date == null ? tr(context, 'Hourly humidity', 'Độ ẩm theo giờ') : '${tr(context, 'Hourly humidity', 'Độ ẩm theo giờ')} · ${f.dayShort(date)}',
                style: TextStyle(color: c.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
              ),
              if (sec.isStale) SectionNotice(status: sec.status, reason: sec.reasonCode, compact: true),
              const SizedBox(height: 8),
              HourChart(
                labels: labels,
                unitLabel: '%',
                minY: 0,
                maxY: 100,
                yFormat: (v) => '${v.round()}%',
                selected: sel,
                onSelect: onSelect,
                series: [ChartSeries(values: [for (final h in hours) h.humidityPct], color: c.blue, kind: SeriesKind.bar)],
              ),
              if (sel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${fullLabels[sel]} · ${f.pct(hours[sel].humidityPct)} · ${tr(context, 'dew point', 'điểm sương')} ${f.deg(hours[sel].dewPointC)}',
                    style: TextStyle(color: c.textPrimary, fontSize: 13),
                  ),
                ),
              SourceFooter(source: sec.source, timezone: loc.timezone, stale: sec.isStale),
            ],
          ),
        ),
        TwoUp(
          a: StatTile(
            icon: Icons.arrow_upward_rounded,
            iconColor: c.accent,
            label: tr(context, 'Highest', 'Cao nhất'),
            value: f.pct(hMax?.value),
            caption: extremeTime(f, hMax),
          ),
          b: StatTile(
            icon: Icons.arrow_downward_rounded,
            iconColor: c.blue,
            label: tr(context, 'Lowest', 'Thấp nhất'),
            value: f.pct(hMin?.value),
            caption: extremeTime(f, hMin),
          ),
        ),
        if (coverage != null) Text(coverage, style: TextStyle(color: c.textMuted, fontSize: 12)),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(10, 14, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr(context, 'Dew point', 'Điểm sương'), style: TextStyle(color: c.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (!hasDew)
                Text(tr(context, 'Dew point is not available for this day', 'Chưa có dữ liệu điểm sương cho ngày này'), style: TextStyle(color: c.textSecondary))
              else
                HourChart(
                  labels: labels,
                  unitLabel: f.tempUnit,
                  yFormat: (v) => '${v.round()}°',
                  selected: sel,
                  onSelect: onSelect,
                  series: [ChartSeries(values: [for (final h in hours) f.temp(h.dewPointC)], color: c.accent, fill: true)],
                ),
            ],
          ),
        ),
        HourTable(
          headers: [
            tr(context, 'Time', 'Giờ'),
            '',
            tr(context, 'Humidity', 'Độ ẩm'),
            tr(context, 'Dew point', 'Điểm sương'),
            tr(context, 'Level', 'Mức'),
          ],
          flex: const [4, 2, 3, 3, 3],
          selected: sel,
          onTap: onSelect,
          rows: [
            for (var k = 0; k < hours.length; k++)
              [
                Text(fullLabels[k], style: TextStyle(color: c.textPrimary)),
                WeatherIcon(code: hours[k].conditionCode, isDay: hours[k].isDay, size: 26),
                Text(f.pct(hours[k].humidityPct), style: TextStyle(color: c.blue, fontWeight: FontWeight.w600)),
                Text(f.deg(hours[k].dewPointC), style: TextStyle(color: c.textPrimary)),
                Text(_shortLabel(context, _labelCode(hours[k].humidityPct, thresholds)), style: TextStyle(color: c.textSecondary)),
              ],
          ],
        ),
      ],
    ]);
  }
}
