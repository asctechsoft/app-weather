import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../home/home_screen.dart' show AqiScale;
import '../metrics/charts_b.dart';

/// AQ01. US AQI from a model source (CAMS); never presented as a monitoring station.
class AirQualityScreen extends StatelessWidget {
  const AirQualityScreen({super.key, required this.location});
  final Location location;

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: tr(context, 'Air quality', 'Chất lượng không khí'),
      subtitle: location.name,
      body: AsyncLoader<Json>(
        load: () => ApiClient.instance.airQuality(location.locationId),
        builder: (context, json, reload) => _AirBody(json: json, location: location, reload: reload),
      ),
    );
  }
}

/// Mirrors the server's US AQI breakpoints (0-50, 51-100, 101-150, 151-200, 201-300, 301+).
String _aqiCat(double v) {
  final r = v.round();
  if (r <= 50) return 'good';
  if (r <= 100) return 'moderate';
  if (r <= 150) return 'unhealthy_sensitive';
  if (r <= 200) return 'unhealthy';
  if (r <= 300) return 'very_unhealthy';
  return 'hazardous';
}

const _aqiCats = ['good', 'moderate', 'unhealthy_sensitive', 'unhealthy', 'very_unhealthy', 'hazardous'];
const _aqiRanges = ['0–50', '51–100', '101–150', '151–200', '201–300', '301+'];

/// General guidance per category, following AirNow wording.
String _aqiGuidance(BuildContext context, String? cat) => switch (cat) {
      'good' => tr(context, 'Air quality is satisfactory, and air pollution poses little or no risk.', 'Chất lượng không khí đạt yêu cầu, ô nhiễm gây ít hoặc không có rủi ro.'),
      'moderate' => tr(context, 'Air quality is acceptable. Some people who are unusually sensitive to air pollution may be at risk.',
          'Chất lượng không khí chấp nhận được. Một số người đặc biệt nhạy cảm với ô nhiễm có thể gặp rủi ro.'),
      'unhealthy_sensitive' => tr(context, 'Members of sensitive groups may experience health effects. The general public is less likely to be affected.',
          'Nhóm nhạy cảm có thể bị ảnh hưởng sức khỏe. Người dân nói chung ít bị ảnh hưởng hơn.'),
      'unhealthy' => tr(context, 'Some members of the general public may experience health effects; sensitive groups may experience more serious effects.',
          'Một số người có thể bị ảnh hưởng sức khỏe; nhóm nhạy cảm có thể bị ảnh hưởng nghiêm trọng hơn.'),
      'very_unhealthy' => tr(context, 'Health alert: the risk of health effects is increased for everyone.', 'Cảnh giác sức khỏe: nguy cơ ảnh hưởng sức khỏe tăng với mọi người.'),
      'hazardous' => tr(context, 'Health warning of emergency conditions: everyone is more likely to be affected.', 'Cảnh báo sức khỏe khẩn cấp: mọi người đều dễ bị ảnh hưởng hơn.'),
      _ => tr(context, 'Air quality value is not available right now.', 'Hiện chưa có giá trị chất lượng không khí.'),
    };

class _AirBody extends StatelessWidget {
  const _AirBody({required this.json, required this.location, required this.reload});
  final Json json;
  final Location location;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final tz = location.timezone;
    final current = Section.parse(json['current'], (v) => m(v)!);
    final tomorrow = Section.parse(json['tomorrow'], (v) => m(v)!);
    final hourly = Section.parse(json['hourly'], (v) => lm(v));
    final unit = s(json['concentrationUnit']) ?? 'μg/m³';
    final cur = current.data;
    final aqi = d(cur?['usAqi']);
    final cat = s(cur?['category']) ?? (aqi == null ? null : _aqiCat(aqi));
    final catColor = SkyPalette.aqiColor(cat);
    final localDate = s(json['localDate']);
    final hours = (hourly.data ?? const <Json>[]).where((h) => localDate == null || s(h['localDate']) == localDate).toList();

    final hero = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('US AQI'),
          noticeFor(current, onRetry: reload),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ValueOrReason(value: f.number(aqi), style: TextStyle(fontSize: 60, height: 1.1, fontWeight: FontWeight.w700, color: aqi == null ? c.textPrimary : catColor)),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(aqiCategoryLabel(context, cat), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: catColor)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AqiScale(value: aqi),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (final t in ['0', '50', '100', '150', '200', '300', '500']) Text(t, style: TextStyle(fontSize: 11, color: c.textSecondary))],
          ),
          const SizedBox(height: 12),
          Text(_aqiGuidance(context, cat), style: TextStyle(color: c.textSecondary, height: 1.4)),
          SourceFooter(source: current.source, timezone: tz, stale: current.isStale),
        ],
      ),
    );

    final hourlyCard = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: tr(context, 'Hourly AQI today', 'AQI theo giờ hôm nay'), trailing: 'US AQI'),
          noticeFor(hourly, onRetry: reload),
          if (hours.isNotEmpty) ...[
            const SizedBox(height: 12),
            BarSeriesChart(
              values: [for (final h in hours) d(h['usAqi'])],
              labels: [for (final h in hours) f.wallHour(s(h['localTime']))],
              colorOf: (v) => SkyPalette.aqiColor(_aqiCat(v)),
              valueText: (v) => v.round().toString(),
              labelEvery: 3,
              minTop: 100,
              semanticLabel: tr(context, 'Hourly US AQI chart', 'Biểu đồ US AQI theo giờ'),
            ),
          ],
          SourceFooter(source: hourly.source, timezone: tz, stale: hourly.isStale),
        ],
      ),
    );

    final t = tomorrow.data;
    final tMax = d(t?['maxUsAqi']);
    final tCat = s(t?['category']) ?? (tMax == null ? null : _aqiCat(tMax));
    final tDate = s(t?['localDate']);
    final tomorrowCard = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: tr(context, 'Tomorrow', 'Ngày mai'), trailing: tDate == null ? null : f.dayShort(tDate)),
          noticeFor(tomorrow, onRetry: reload),
          if (t != null) ...[
            const SizedBox(height: 8),
            Text(tr(context, 'Highest forecast tomorrow', 'Cao nhất dự báo ngày mai'), style: TextStyle(color: c.textSecondary, fontSize: 13)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ValueOrReason(value: f.number(tMax), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: tMax == null ? c.textPrimary : SkyPalette.aqiColor(tCat))),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(aqiCategoryLabel(context, tCat), style: TextStyle(color: SkyPalette.aqiColor(tCat), fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
            if (t['localTime'] != null)
              Text('${tr(context, 'Around', 'Khoảng')} ${f.wallTime(s(t['localTime']))}', style: TextStyle(color: c.textSecondary, fontSize: 13)),
          ],
          SourceFooter(source: tomorrow.source, timezone: tz, stale: tomorrow.isStale),
        ],
      ),
    );

    String conc(Object? v) {
      final x = d(v);
      if (x == null) return Fmt.dash;
      return x < 10 ? x.toStringAsFixed(1) : x.round().toString();
    }

    final pollutants = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: tr(context, 'Main pollutants', 'Chất ô nhiễm chính'), trailing: unit),
          const SizedBox(height: 12),
          ResponsiveGrid(
            minTwoColWidth: 240,
            children: [
              for (final (key, name, desc) in [
                ('pm25', 'PM2.5', tr(context, 'Fine particles', 'Bụi mịn')),
                ('pm10', 'PM10', tr(context, 'Coarse particles', 'Bụi thô')),
                ('no2', 'NO₂', tr(context, 'Nitrogen dioxide', 'Nitơ điôxít')),
                ('o3', 'O₃', tr(context, 'Ozone', 'Ôzôn')),
              ])
                _PollutantTile(name: name, desc: desc, value: conc(cur?[key]), unit: unit),
            ],
          ),
          SourceFooter(source: current.source, timezone: tz, stale: current.isStale),
        ],
      ),
    );

    final coord = m(json['dataCoordinate']);
    final station = m(json['station']);
    String coordText() {
      final lat = d(coord?['latitude']);
      final lon = d(coord?['longitude']);
      if (lat == null || lon == null) return Fmt.dash;
      return '${lat.abs().toStringAsFixed(2)}°${lat >= 0 ? 'N' : 'S'}, ${lon.abs().toStringAsFixed(2)}°${lon >= 0 ? 'E' : 'W'}';
    }

    final stationCard = GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(station == null ? Icons.grid_on_rounded : Icons.sensors_rounded, color: c.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  station == null
                      ? tr(context, 'Model data (CAMS), not a monitoring station', 'Dữ liệu mô hình (CAMS), không phải trạm quan trắc')
                      : (s(station['name']) ?? tr(context, 'Monitoring station', 'Trạm quan trắc')),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.textPrimary),
                ),
                const SizedBox(height: 6),
                if (station == null) ...[
                  Text(
                    tr(context, 'Values are estimated by an atmospheric model for a grid cell near this place, not measured at a station.',
                        'Giá trị được ước tính bởi mô hình khí quyển cho ô lưới gần địa điểm này, không phải đo tại trạm.'),
                    style: TextStyle(color: c.textSecondary, height: 1.35),
                  ),
                  const SizedBox(height: 6),
                  Text('${tr(context, 'Model grid point', 'Điểm lưới mô hình')}: ${coordText()}', style: TextStyle(color: c.textMuted, fontSize: 13)),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    final about = GlassCard(
      onTap: () => _showAqiSheet(context),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: c.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'About US AQI', 'Về chỉ số US AQI'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.textPrimary)),
                const SizedBox(height: 4),
                Text(tr(context, 'Six categories from Good to Hazardous. Tap to learn more.', 'Sáu mức từ Tốt đến Nguy hại. Chạm để xem thêm.'), style: TextStyle(color: c.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.textMuted),
        ],
      ),
    );

    return PageList(
      children: [
        hero,
        hourlyCard,
        tomorrowCard,
        pollutants,
        stationCard,
        about,
        AlertsUnavailableCard(
          title: tr(context, 'Air quality alerts', 'Cảnh báo chất lượng không khí'),
          message: tr(context, 'Notifications are not available in this version of the app.', 'Thông báo chưa có trong phiên bản ứng dụng này.'),
        ),
      ],
    );
  }

  void _showAqiSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final c = SkyColors.of(sheetCtx);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetCtx).size.height * .8),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(tr(context, 'About US AQI', 'Về chỉ số US AQI'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.textPrimary)),
                const SizedBox(height: 6),
                Text(
                  tr(context, 'The US Air Quality Index (EPA / AirNow) runs from 0 to 500. Higher values mean more air pollution and greater health concern.',
                      'Chỉ số chất lượng không khí Hoa Kỳ (EPA / AirNow) từ 0 đến 500. Giá trị càng cao, ô nhiễm càng nhiều và càng đáng lo ngại cho sức khỏe.'),
                  style: TextStyle(color: c.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 12),
                for (var k = 0; k < _aqiCats.length; k++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 14, height: 14, margin: const EdgeInsets.only(top: 3), decoration: BoxDecoration(shape: BoxShape.circle, color: SkyPalette.aqi[k])),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${_aqiRanges[k]} · ${aqiCategoryLabel(context, _aqiCats[k])}', style: TextStyle(fontWeight: FontWeight.w600, color: c.textPrimary)),
                              const SizedBox(height: 2),
                              Text(_aqiGuidance(context, _aqiCats[k]), style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  tr(context, 'US AQI is not the same as the European AQI or other national indices.', 'US AQI không giống European AQI hoặc chỉ số quốc gia khác.'),
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PollutantTile extends StatelessWidget {
  const _PollutantTile({required this.name, required this.desc, required this.value, required this.unit});
  final String name;
  final String desc;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: c.cardBorder), color: c.chipBg.withValues(alpha: .4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
          Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.textSecondary)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ValueOrReason(value: value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: c.textPrimary)),
              const SizedBox(width: 4),
              Flexible(child: Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(unit, style: TextStyle(fontSize: 12, color: c.textSecondary)))),
            ],
          ),
        ],
      ),
    );
  }
}
