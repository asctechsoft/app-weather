import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'charts_b.dart';

/// UV01. Hero = UV now; dailyMax is a different value labelled as today's maximum.
class UvScreen extends StatelessWidget {
  const UvScreen({super.key, required this.location});
  final Location location;

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: tr(context, 'UV index', 'Chỉ số UV'),
      subtitle: location.name,
      body: AsyncLoader<Json>(
        load: () => ApiClient.instance.metric('uv', location.locationId),
        builder: (context, json, reload) => _UvBody(json: json, location: location, reload: reload),
      ),
    );
  }
}

/// Category from the unrounded value (EPA bands), used only for bar colours.
String _uvCat(double v) {
  if (v < 3) return 'low';
  if (v < 6) return 'moderate';
  if (v < 8) return 'high';
  if (v < 11) return 'very_high';
  return 'extreme';
}

String _uvAdvice(BuildContext context, String? cat) => switch (cat) {
      'low' => tr(context, 'Low risk for most people. Protection is still useful if you stay outside for long.', 'Nguy cơ thấp với đa số người. Vẫn nên che chắn nếu ở ngoài trời lâu.'),
      'moderate' => tr(context, 'Moderate risk. Seek shade around midday and use sunscreen.', 'Nguy cơ trung bình. Tìm bóng râm vào buổi trưa và dùng kem chống nắng.'),
      'high' => tr(context, 'High risk of sunburn. Use sunscreen, a hat and shade.', 'Nguy cơ cháy nắng cao. Dùng kem chống nắng, đội mũ và tìm bóng râm.'),
      'very_high' => tr(context, 'Very high risk. Take extra precautions and limit midday sun.', 'Nguy cơ rất cao. Che chắn kỹ và hạn chế nắng buổi trưa.'),
      'extreme' => tr(context, 'Extreme risk. Avoid the midday sun; protect skin and eyes.', 'Nguy cơ cực cao. Tránh nắng buổi trưa; bảo vệ da và mắt.'),
      _ => tr(context, 'UV value is not available right now.', 'Hiện chưa có giá trị UV.'),
    };

class _UvBody extends StatelessWidget {
  const _UvBody({required this.json, required this.location, required this.reload});
  final Json json;
  final Location location;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final summary = m(json['summary']);
    final section = Section.parse(json['section'], HourlyRecord.list);
    final current = m(summary?['current']);
    final uv = d(current?['uvIndex']);
    final cat = s(current?['category']);
    final dailyMax = m(summary?['dailyMax']);
    final maxUv = d(dailyMax?['uvIndex']);
    final maxCat = s(dailyMax?['category']);
    final peak = Extremum.from(summary?['peak']);
    final strong = m(summary?['strongWindow']);
    final threshold = d(summary?['strongThreshold']) ?? 6;
    final hourlyAvailable = summary?['hourlyAvailable'] != false;
    final hours = section.data ?? const <HourlyRecord>[];
    final color = SkyPalette.uvColor(cat);

    final hero = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.wb_sunny_rounded, size: 60, color: uv == null ? c.textMuted : color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, 'UV index now', 'Chỉ số UV hiện tại'), style: TextStyle(color: c.textPrimary, fontSize: 18)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        ValueOrReason(value: f.uv(uv), style: TextStyle(fontSize: 60, height: 1.1, fontWeight: FontWeight.w600, color: uv == null ? c.textPrimary : color)),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(uvCategoryLabel(context, cat), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: color)),
                        ),
                      ],
                    ),
                    Text(_uvAdvice(context, cat), style: TextStyle(color: c.textSecondary, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GradientScale(
            colors: SkyPalette.uv,
            position: uv == null ? null : uv / 11,
            markerColor: color,
            ticks: [for (var k = 0; k <= 10; k++) '$k', '11+'],
          ),
          const SizedBox(height: 12),
          Divider(color: c.divider, height: 1),
          const SizedBox(height: 8),
          KeyValueRow(
            icon: Icons.arrow_upward_rounded,
            iconColor: SkyPalette.uvColor(maxCat),
            label: tr(context, 'Maximum today', 'Cực đại hôm nay'),
            value: maxUv == null ? Fmt.dash : '${f.uv(maxUv)} · ${uvCategoryLabel(context, maxCat)}',
          ),
          if (current?['validAt'] != null)
            Text('${tr(context, 'Current value valid at', 'Giá trị hiện tại lúc')} ${f.time(s(current?['validAt']), location.timezone)}',
                style: TextStyle(color: c.textMuted, fontSize: 12)),
        ],
      ),
    );

    Widget chartCard;
    if (!hourlyAvailable) {
      chartCard = GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardHeader(title: tr(context, 'Hourly UV index', 'UV theo giờ')),
            const SizedBox(height: 8),
            Text(
              tr(context, 'Hourly UV is not available for this place. Only today\'s maximum is shown.', 'Không có UV theo giờ cho địa điểm này. Chỉ hiển thị cực đại hôm nay.'),
              style: TextStyle(color: c.textSecondary),
            ),
            KeyValueRow(label: tr(context, 'Maximum today', 'Cực đại hôm nay'), value: f.uv(maxUv)),
            SourceFooter(source: section.source, timezone: location.timezone, stale: section.isStale),
          ],
        ),
      );
    } else {
      chartCard = GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardHeader(title: tr(context, 'Hourly UV index', 'UV theo giờ')),
            if (peak != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr(context, 'Peak today: ${f.uv(peak.value)} at ${f.wallTime(peak.localTime)}', 'Cao nhất hôm nay: ${f.uv(peak.value)} lúc ${f.wallTime(peak.localTime)}'),
                  style: TextStyle(color: c.blue, fontSize: 14),
                ),
              ),
            noticeFor(section, onRetry: reload),
            if (hours.isNotEmpty) ...[
              const SizedBox(height: 12),
              BarSeriesChart(
                values: [for (final h in hours) h.uvIndex],
                labels: [for (final h in hours) f.wallHour(h.localTime)],
                colorOf: (v) => v <= 0 ? c.blue.withValues(alpha: .6) : SkyPalette.uvColor(_uvCat(v)),
                valueText: (v) => f.uv(v),
                labelEvery: 3,
                minTop: 8,
                semanticLabel: tr(context, 'Hourly UV index chart', 'Biểu đồ UV theo giờ'),
              ),
            ],
            SourceFooter(source: section.source, timezone: location.timezone, stale: section.isStale),
          ],
        ),
      );
    }

    final protect = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: tr(context, 'Protect yourself', 'Bảo vệ bản thân')),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _ProtectTile(icon: Icons.sanitizer_outlined, color: const Color(0xFFFFB648), title: tr(context, 'Sunscreen', 'Kem chống nắng'), body: tr(context, 'Use broad-spectrum sunscreen.', 'Dùng kem chống nắng phổ rộng.'))),
              const SizedBox(width: 8),
              Expanded(child: _ProtectTile(icon: Icons.face_retouching_natural_outlined, color: const Color(0xFFE2C08D), title: tr(context, 'Hat', 'Mũ'), body: tr(context, 'Wear a hat with a wide brim.', 'Đội mũ rộng vành.'))),
              const SizedBox(width: 8),
              Expanded(child: _ProtectTile(icon: Icons.park_outlined, color: const Color(0xFF3CCB7F), title: tr(context, 'Shade', 'Bóng râm'), body: tr(context, 'Seek shade, especially at midday.', 'Tìm bóng râm, nhất là buổi trưa.'))),
            ],
          ),
          const SizedBox(height: 8),
          Text(tr(context, 'General sun-safety education, not personal medical advice.', 'Thông tin chống nắng chung, không phải lời khuyên y tế cá nhân.'),
              style: TextStyle(color: c.textMuted, fontSize: 12)),
        ],
      ),
    );

    final String strongText;
    if (strong != null) {
      strongText = '${f.wallHour(s(strong['fromLocal']))} – ${f.wallHour(s(strong['toLocal']))}';
    } else if (!hourlyAvailable || hours.isEmpty) {
      strongText = Fmt.dash;
    } else {
      strongText = tr(context, 'UV stays below ${f.uv(threshold)} today', 'UV dưới ${f.uv(threshold)} cả ngày hôm nay');
    }
    final strongCard = GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_rounded, color: c.blue, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'Strongest UV', 'UV mạnh nhất'), style: TextStyle(fontSize: 17, color: c.textPrimary)),
                const SizedBox(height: 4),
                ValueOrReason(
                  value: strongText,
                  reason: tr(context, 'Hourly UV is not available', 'Không có UV theo giờ'),
                  style: TextStyle(fontSize: strong != null ? 28 : 20, fontWeight: FontWeight.w700, color: c.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(context, 'Hours today with forecast UV of ${f.uv(threshold)} or more.', 'Các giờ hôm nay có UV dự báo từ ${f.uv(threshold)} trở lên.'),
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
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
        chartCard,
        protect,
        strongCard,
        AlertsUnavailableCard(
          title: tr(context, 'UV alerts', 'Cảnh báo UV'),
          message: tr(context, 'Notifications are not available in this version of the app.', 'Thông báo chưa có trong phiên bản ứng dụng này.'),
        ),
        InfoCard(
          icon: Icons.cloud_outlined,
          title: tr(context, 'Clouds don\'t block all UV', 'Mây không chặn hết tia UV'),
          body: tr(context, 'UV rays can still reach you on cloudy days, so keep protecting your skin.', 'Tia UV vẫn có thể tới bạn vào ngày nhiều mây, vì vậy hãy tiếp tục bảo vệ da.'),
        ),
      ],
    );
  }
}

class _ProtectTile extends StatelessWidget {
  const _ProtectTile({required this.icon, required this.color, required this.title, required this.body});
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: c.cardBorder), color: c.chipBg.withValues(alpha: .4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 6),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: c.textPrimary)),
          const SizedBox(height: 2),
          Text(body, style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.3)),
        ],
      ),
    );
  }
}
