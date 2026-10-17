import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/weather_icon.dart';
import '../../ui/widgets.dart';
import '../metrics/charts_a.dart';

/// FC01 Hourly forecast for one local date of the place being viewed.
class HourlyScreen extends StatefulWidget {
  const HourlyScreen({super.key, required this.location, this.date, this.metric = 'temperature'});
  final Location location;
  final String? date;
  final String metric;

  @override
  State<HourlyScreen> createState() => _HourlyScreenState();
}

/// Load result: either a response or a recoverable date error (out of horizon / invalid date).
class _HourlyResult {
  _HourlyResult(this.json, this.error);
  final Json? json;
  final ApiException? error;
}

class _HourlyScreenState extends State<HourlyScreen> {
  String? _date; // requested date; null = server's "today"
  late String _tab;
  int? _selected;

  // From the last successful response (header + date picker after an error).
  String? _shownDate;
  String? _today;
  List<String> _available = const [];

  @override
  void initState() {
    super.initState();
    _date = widget.date;
    _tab = const ['temperature', 'rain', 'wind'].contains(widget.metric) ? widget.metric : 'temperature';
  }

  Future<_HourlyResult> _load() async {
    try {
      final json = await ApiClient.instance.hourly(widget.location.locationId, date: _date);
      if (mounted) {
        setState(() {
          _shownDate = s(json['date']);
          _today = s(json['localDate']);
          final dates = (json['availableDates'] as List?)?.map((e) => e.toString()).toList();
          if (dates != null && dates.isNotEmpty) _available = dates;
        });
      }
      return _HourlyResult(json, null);
    } on ApiException catch (e) {
      if (e.code == 'DATE_OUT_OF_HORIZON' || e.code == 'VALIDATION_ERROR' || e.status == 400) {
        if (mounted) setState(() => _shownDate = _date);
        return _HourlyResult(null, e);
      }
      rethrow;
    }
  }

  void _pickDate(String date) {
    if (date == _date && _shownDate == date) return;
    setState(() {
      _date = date;
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final place = widget.location.name ?? '-';
    final day = _shownDate ?? _date;
    return DetailScaffold(
      title: tr(context, 'Hourly forecast', 'Dự báo theo giờ'),
      subtitle: day == null ? place : '$place · ${f.dayShort(day)}',
      body: AsyncLoader<_HourlyResult>(
        loadKey: _date,
        load: _load,
        builder: (context, res, reload) => res.error != null ? _errorBody(context, res.error!) : _body(context, res.json!),
      ),
    );
  }

  // ---------------- error: let the user choose another date ----------------

  Widget _errorBody(BuildContext context, ApiException e) {
    final c = SkyColors.of(context);
    return PageList(children: [
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.event_busy_rounded, color: c.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(errorText(context, e), style: TextStyle(color: c.textPrimary, fontSize: 16))),
            ]),
            const SizedBox(height: 8),
            Text(tr(context, 'Choose another date:', 'Chọn ngày khác:'), style: TextStyle(color: c.textSecondary)),
            const SizedBox(height: 8),
            if (_available.isNotEmpty)
              _DateChips(dates: _available, selected: null, today: _today, onPick: _pickDate)
            else
              FilledButton(
                onPressed: () => setState(() {
                  _date = null;
                  _selected = null;
                }),
                child: Text(tr(context, 'Go to today', 'Về hôm nay')),
              ),
          ],
        ),
      ),
    ]);
  }

  // ---------------- main body ----------------

  Widget _body(BuildContext context, Json json) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final loc = widget.location;
    final sec = Section.parse(json['section'], HourlyRecord.list);
    final hours = sec.data ?? const <HourlyRecord>[];
    final date = s(json['date']) ?? _date ?? '';
    final today = s(json['localDate']);
    final tomorrow = today == null ? null : addLocalDays(today, 1);
    final dates = (json['availableDates'] as List?)?.map((e) => e.toString()).toList() ?? _available;
    final tempStats = jp(json, 'summary.temperature');
    final minE = Extremum.from(jp(json, 'summary.temperature.min'));
    final maxE = Extremum.from(jp(json, 'summary.temperature.max'));
    final coverage = coverageNote(context, tempStats);
    final sel = _selected != null && _selected! < hours.length ? _selected : null;

    // Date selector: Today / Tomorrow shortcuts + chips for every available date.
    final quick = <(String, String, IconData?)>[
      if (today != null && dates.contains(today)) (today, tr(context, 'Today', 'Hôm nay'), null),
      if (tomorrow != null && dates.contains(tomorrow)) (tomorrow, tr(context, 'Tomorrow', 'Ngày mai'), null),
    ];
    final isQuick = date == today || date == tomorrow;

    return PageList(children: [
      _HeroCard(json: json, location: loc, date: date, isToday: date == today),
      if (quick.length >= 2) PillTabs<String>(items: quick, selected: isQuick ? date : '', onChanged: _pickDate),
      if (!isQuick)
        Row(children: [
          Icon(Icons.event_rounded, size: 18, color: c.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${tr(context, 'Showing', 'Đang xem')} ${f.dayLong(date)}',
              style: TextStyle(color: c.accent, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      if (dates.length > 2) _DateChips(dates: dates, selected: date, today: today, onPick: _pickDate),
      PillTabs<String>(
        items: [
          ('temperature', tr(context, 'Temperature', 'Nhiệt độ'), Icons.thermostat_rounded),
          ('rain', tr(context, 'Rain', 'Mưa'), Icons.water_drop_outlined),
          ('wind', tr(context, 'Wind', 'Gió'), Icons.air_rounded),
        ],
        selected: _tab,
        onChanged: (v) => setState(() => _tab = v), // never changes the date
      ),
      if (!sec.hasData)
        GlassCard(child: SectionNotice(status: sec.status, reason: sec.reasonCode))
      else ...[
        if (sec.isStale) SectionNotice(status: sec.status, reason: sec.reasonCode, compact: true),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(8, 14, 12, 10),
          child: _chart(context, hours, sel, sec),
        ),
        TwoUp(
          a: StatTile(
            icon: Icons.thermostat_rounded,
            iconColor: c.blue,
            label: tr(context, 'Min temperature', 'Nhiệt độ thấp nhất'),
            value: f.deg(minE?.value),
            caption: extremeTime(f, minE),
          ),
          b: StatTile(
            icon: Icons.thermostat_rounded,
            iconColor: c.accent,
            label: tr(context, 'Max temperature', 'Nhiệt độ cao nhất'),
            value: f.deg(maxE?.value),
            valueColor: c.accent,
            caption: extremeTime(f, maxE),
          ),
        ),
        if (coverage != null) Text(coverage, style: TextStyle(color: c.textMuted, fontSize: 12)),
        _table(context, hours, sel, sec),
      ],
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.info_outline_rounded, color: c.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(context, 'Tap a point or a row for details', 'Chạm một điểm hoặc một hàng để xem chi tiết'),
                  style: TextStyle(color: c.textPrimary),
                ),
              ),
            ]),
            SourceFooter(source: sec.source, timezone: loc.timezone, stale: sec.isStale),
          ],
        ),
      ),
    ]);
  }

  void _select(List<HourlyRecord> hours, int k, Section<List<HourlyRecord>> sec) {
    setState(() => _selected = k);
    _showHourSheet(context, hours, k, sec);
  }

  Widget _chart(BuildContext context, List<HourlyRecord> hours, int? sel, Section<List<HourlyRecord>> sec) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final labels = hourLabels(hours, f);
    void onSelect(int k) => _select(hours, k, sec);
    switch (_tab) {
      case 'rain':
        final inches = f.precipUnit == 'in';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChartLegend(items: [(c.blue, tr(context, 'Chance of rain (%)', 'Khả năng mưa (%)'))]),
            const SizedBox(height: 6),
            HourChart(
              labels: labels,
              unitLabel: '%',
              minY: 0,
              maxY: 100,
              height: 150,
              yFormat: (v) => '${v.round()}%',
              selected: sel,
              onSelect: onSelect,
              series: [ChartSeries(values: [for (final h in hours) h.rainProbabilityPct], color: c.blue, kind: SeriesKind.bar)],
            ),
            const SizedBox(height: 14),
            ChartLegend(items: [(const Color(0xFF5AB4FF), tr(context, 'Precipitation amount', 'Lượng mưa'))]),
            const SizedBox(height: 6),
            HourChart(
              labels: labels,
              unitLabel: '${f.precipUnit} ${tr(context, 'per hour (amount in the preceding hour)', 'mỗi giờ (lượng trong giờ trước đó)')}',
              minY: 0,
              height: 150,
              yFormat: (v) => v.toStringAsFixed(inches ? 2 : 1),
              selected: sel,
              onSelect: onSelect,
              series: [ChartSeries(values: [for (final h in hours) f.precip(h.precipitationMm)], color: const Color(0xFF5AB4FF), kind: SeriesKind.bar)],
            ),
          ],
        );
      case 'wind':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChartLegend(items: [(c.blue, tr(context, 'Wind', 'Gió')), (c.accent, tr(context, 'Gusts', 'Gió giật'))]),
            const SizedBox(height: 6),
            HourChart(
              labels: labels,
              unitLabel: f.windUnit,
              minY: 0,
              selected: sel,
              onSelect: onSelect,
              series: [
                ChartSeries(values: [for (final h in hours) f.wind(h.windSpeedMs)], color: c.blue, fill: true),
                ChartSeries(values: [for (final h in hours) f.wind(h.windGustMs)], color: c.accent),
              ],
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChartLegend(items: [(c.accent, tr(context, 'Temperature', 'Nhiệt độ')), (c.blue, tr(context, 'Feels like', 'Cảm giác như'))]),
            const SizedBox(height: 6),
            HourChart(
              labels: labels,
              unitLabel: f.tempUnit,
              yFormat: (v) => '${v.round()}°',
              selected: sel,
              onSelect: onSelect,
              series: [
                ChartSeries(values: [for (final h in hours) f.temp(h.temperatureC)], color: c.accent, fill: true),
                ChartSeries(values: [for (final h in hours) f.temp(h.feelsLikeC)], color: c.blue, strokeWidth: 2),
              ],
            ),
          ],
        );
    }
  }

  Widget _table(BuildContext context, List<HourlyRecord> hours, int? sel, Section<List<HourlyRecord>> sec) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final labels = hourLabels(hours, f, full: true);
    final wind = _tab == 'wind';
    final rain = _tab == 'rain';
    final headers = [
      tr(context, 'Time', 'Giờ'),
      tr(context, 'Weather', 'Thời tiết'),
      tr(context, 'Temp', 'Nhiệt độ'),
      tr(context, 'Feels like', 'Cảm giác'),
      tr(context, 'Rain', 'Mưa'),
      if (wind) tr(context, 'Wind', 'Gió'),
      if (rain) f.precipUnit,
    ];
    final rows = <List<Widget>>[
      for (var k = 0; k < hours.length; k++)
        [
          Text(labels[k], style: TextStyle(color: c.textPrimary)),
          WeatherIcon(code: hours[k].conditionCode, isDay: hours[k].isDay, size: 28),
          Text(f.deg(hours[k].temperatureC), style: TextStyle(color: c.accent, fontSize: 17, fontWeight: FontWeight.w600)),
          Text(f.deg(hours[k].feelsLikeC), style: TextStyle(color: c.textPrimary)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.water_drop_rounded, size: 14, color: c.blue),
            const SizedBox(width: 3),
            Text(f.pct(hours[k].rainProbabilityPct), style: TextStyle(color: c.textPrimary)),
          ]),
          if (wind) Text(f.windNum(hours[k].windSpeedMs), style: TextStyle(color: c.textPrimary)),
          if (rain) Text(f.precipNum(hours[k].precipitationMm), style: TextStyle(color: c.textPrimary)),
        ],
    ];
    return HourTable(
      headers: headers,
      flex: [5, 3, 3, 3, 3, if (wind || rain) 3],
      rows: rows,
      selected: sel,
      onTap: (k) => _select(hours, k, sec),
    );
  }

  void _showHourSheet(BuildContext context, List<HourlyRecord> hours, int k, Section<List<HourlyRecord>> sec) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final tz = widget.location.timezone;
    final h = hours[k];
    final label = hourLabels(hours, f, full: true)[k];
    final compass = compassFromDeg(h.windDirectionDeg, h.windSpeedMs);
    final src = sec.source;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                WeatherIcon(code: h.conditionCode, isDay: h.isDay, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${f.dayShort(h.localDate)} · $label', style: TextStyle(color: c.textSecondary)),
                      Text(conditionLabel(context, h.conditionCode, isDay: h.isDay),
                          style: TextStyle(color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Divider(color: c.divider),
              KeyValueRow(label: tr(context, 'Temperature', 'Nhiệt độ'), value: f.degU(h.temperatureC)),
              KeyValueRow(label: tr(context, 'Feels like', 'Cảm giác như'), value: f.degU(h.feelsLikeC)),
              KeyValueRow(label: tr(context, 'Chance of rain', 'Khả năng mưa'), value: f.pct(h.rainProbabilityPct)),
              KeyValueRow(
                label: tr(context, 'Precipitation', 'Lượng mưa'),
                value: f.precipU(h.precipitationMm),
                sub: '${f.time(h.intervalStartAt, tz)} – ${f.time(h.intervalEndAt, tz)}',
              ),
              KeyValueRow(label: tr(context, 'Wind', 'Gió'), value: f.windU(h.windSpeedMs)),
              KeyValueRow(label: tr(context, 'Gusts', 'Gió giật'), value: f.windU(h.windGustMs)),
              KeyValueRow(
                label: tr(context, 'Wind from', 'Hướng gió từ'),
                value: compassText(context, compass),
                sub: compass == null || h.windDirectionDeg == null ? null : '${h.windDirectionDeg!.round()}°',
              ),
              KeyValueRow(label: tr(context, 'Humidity', 'Độ ẩm'), value: f.pct(h.humidityPct)),
              KeyValueRow(label: tr(context, 'UV index', 'Chỉ số UV'), value: f.uv(h.uvIndex)),
              KeyValueRow(
                label: tr(context, 'Source', 'Nguồn'),
                value: src == null ? Fmt.dash : providerName(src.providerId),
                sub: src == null ? null : dataKindLabel(context, src.dataKind),
              ),
              Text(
                '${tr(context, 'Valid at', 'Thời điểm')} ${f.time(h.time, tz)} (${utcOffsetLabel(h.utcOffsetSeconds)})',
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.json, required this.location, required this.date, required this.isToday});
  final Json json;
  final Location location;
  final String date;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final cur = m(json['current']);
    final day = m(jp(json, 'summary.day'));
    final code = isToday ? (s(cur?['conditionCode']) ?? 'UNKNOWN') : (s(day?['conditionCode']) ?? 'UNKNOWN');
    final isDay = isToday ? (cur?['isDay'] as bool?) : true;
    final showCurrent = isToday && cur != null;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(location.name ?? '-',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: c.textPrimary)),
                  ),
                  const SizedBox(width: 6),
                  Icon(location.isGps ? Icons.near_me_outlined : Icons.place_outlined, size: 18, color: c.textSecondary),
                ]),
                Text(f.dayShort(date), style: TextStyle(color: c.textSecondary, fontSize: 15)),
                const SizedBox(height: 4),
                if (showCurrent)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(f.deg(d(cur['temperatureC'])), style: TextStyle(fontSize: 64, height: 1.1, fontWeight: FontWeight.w300, color: c.accent)),
                        const SizedBox(width: 8),
                        Text(tr(context, 'Now', 'Bây giờ'), style: TextStyle(fontSize: 18, color: c.textPrimary)),
                      ],
                    ),
                  )
                else
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'H ${f.deg(d(day?['maxC']))}  ·  L ${f.deg(d(day?['minC']))}',
                      style: TextStyle(fontSize: 34, height: 1.3, fontWeight: FontWeight.w400, color: c.accent),
                    ),
                  ),
                Text(
                  (showCurrent || day != null) ? conditionLabel(context, code, isDay: isDay) : Fmt.dash,
                  style: TextStyle(fontSize: 18, color: c.textPrimary),
                ),
              ],
            ),
          ),
          WeatherIcon(code: code, isDay: isDay, size: 84),
        ],
      ),
    );
  }
}

/// Horizontal chips for every available date (keeps a non-shortcut date visible and selectable).
class _DateChips extends StatelessWidget {
  const _DateChips({required this.dates, required this.selected, required this.today, required this.onPick});
  final List<String> dates;
  final String? selected;
  final String? today;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, k) {
          final dt = dates[k];
          final on = dt == selected;
          return ChoiceChip(
            selected: on,
            onSelected: (_) => onPick(dt),
            showCheckmark: false,
            selectedColor: c.accent,
            backgroundColor: c.chipBg,
            side: BorderSide(color: on ? c.accent : c.cardBorder),
            label: Text(
              dt == today ? tr(context, 'Today', 'Hôm nay') : f.dayShort(dt),
              style: TextStyle(color: on ? const Color(0xFF1A1020) : c.textSecondary, fontWeight: FontWeight.w600),
            ),
          );
        },
      ),
    );
  }
}
