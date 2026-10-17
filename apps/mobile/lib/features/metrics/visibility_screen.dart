import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'charts_b.dart';

/// VIS01. The mountain scene is an illustration, not a view of the place.
class VisibilityScreen extends StatelessWidget {
  const VisibilityScreen({super.key, required this.location});
  final Location location;

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: tr(context, 'Visibility', 'Tầm nhìn'),
      subtitle: location.name,
      body: AsyncLoader<Json>(
        load: () => ApiClient.instance.metric('visibility', location.locationId),
        builder: (context, json, reload) => _VisibilityBody(json: json, location: location, reload: reload),
      ),
    );
  }
}

class _VisibilityBody extends StatelessWidget {
  const _VisibilityBody({required this.json, required this.location, required this.reload});
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
    final vis = d(current?['visibilityM']);
    final cat = s(current?['category']);
    final dayRange = m(summary?['visibility']);
    final dMin = Extremum.from(dayRange?['min']);
    final dMax = Extremum.from(dayRange?['max']);
    final tomorrow = m(summary?['tomorrow']);

    final hero = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: c.cardBorder), borderRadius: BorderRadius.circular(18)),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _MountainPainter(haze: _hazeFor(cat)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(context, 'Visibility now', 'Tầm nhìn hiện tại'), style: const TextStyle(color: Colors.white, fontSize: 17)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ValueOrReason(value: f.distanceU(vis), style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w600, height: 1.15)),
                  ),
                  Text(visibilityLabelText(context, cat), style: const TextStyle(color: Color(0xFFDDE6FF), fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 70),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          current?['validAt'] == null ? '' : '${tr(context, 'Valid at', 'Hiệu lực lúc')} ${f.time(s(current?['validAt']), location.timezone)}',
                          style: const TextStyle(color: Color(0xFFDDE6FF), fontSize: 12),
                        ),
                      ),
                      Text(tr(context, 'Illustration', 'Hình minh họa'), style: const TextStyle(color: Color(0xCCDDE6FF), fontSize: 11, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    String distNum(double v) => v >= 10 ? v.round().toString() : v.toStringAsFixed(1);

    final chart = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: tr(context, 'Today', 'Hôm nay'), trailing: f.distanceUnit),
          if (dMin != null && dMax != null)
            Text('${tr(context, 'Range', 'Khoảng')} ${f.distanceNum(dMin.value)}–${f.distanceU(dMax.value)}', style: TextStyle(color: c.textSecondary, fontSize: 13)),
          noticeFor(section, onRetry: reload),
          if (hours.isNotEmpty) ...[
            const SizedBox(height: 12),
            BarSeriesChart(
              values: [for (final h in hours) f.distance(h.visibilityM)],
              labels: [for (final h in hours) f.wallHour(h.localTime)],
              colorOf: (_) => c.blue,
              valueText: distNum,
              labelEvery: 3,
              semanticLabel: tr(context, 'Visibility chart for today', 'Biểu đồ tầm nhìn hôm nay'),
            ),
          ],
          SourceFooter(source: section.source, timezone: location.timezone, stale: section.isStale),
        ],
      ),
    );

    final tiles = ResponsiveGrid(
      children: [
        StatTile(
          icon: Icons.water_drop_outlined,
          iconColor: c.blue,
          label: tr(context, 'Humidity', 'Độ ẩm'),
          value: f.pct(d(current?['humidityPct'])),
          caption: tr(context, 'Very moist air can favour haze or fog.', 'Không khí rất ẩm có thể dễ tạo mù hoặc sương mù.'),
        ),
        StatTile(
          icon: Icons.cloud_outlined,
          iconColor: c.blue,
          label: tr(context, 'Cloud cover', 'Mây che phủ'),
          value: f.pct(d(current?['cloudCoverPct'])),
          caption: tr(context, 'Describes the sky; it does not set how far you see near the ground.', 'Mô tả bầu trời; không quyết định tầm nhìn gần mặt đất.'),
        ),
      ],
    );

    Widget tomorrowCard() {
      final tr0 = m(tomorrow?['range']);
      final tMin = Extremum.from(tr0?['min']);
      final tMax = Extremum.from(tr0?['max']);
      final date = s(tomorrow?['localDate']);
      final used = i(tomorrow?['hoursUsed']);
      final tVis = d(tomorrow?['visibilityM']);
      final tCat = s(tomorrow?['category']);
      return GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardHeader(title: tr(context, 'Tomorrow', 'Ngày mai'), trailing: date == null ? null : f.dayShort(date)),
            const SizedBox(height: 8),
            if (tomorrow == null)
              SectionNotice(status: 'empty', reason: 'NO_DATA', compact: true)
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ValueOrReason(value: f.distanceU(tVis), style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: c.textPrimary)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(visibilityLabelText(context, tCat), style: TextStyle(color: c.textSecondary, fontSize: 15)),
                    ),
                  ),
                ],
              ),
              Text(
                used == null
                    ? tr(context, 'Typical daytime value (median)', 'Giá trị ban ngày điển hình (trung vị)')
                    : tr(context, 'Typical daytime value (median of $used hours)', 'Giá trị ban ngày điển hình (trung vị của $used giờ)'),
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
              if (tMin != null && tMax != null)
                Text(
                  '${tr(context, 'Daytime range', 'Khoảng ban ngày')} ${f.distanceNum(tMin.value)}–${f.distanceU(tMax.value)}',
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                ),
            ],
          ],
        ),
      );
    }

    return PageList(
      children: [
        hero,
        chart,
        tiles,
        InfoCard(
          title: tr(context, 'About visibility', 'Về tầm nhìn'),
          body: tr(
            context,
            'Visibility is how far you can clearly see objects. Fog, mist, haze, smoke, dust and heavy rain or snow can reduce it.',
            'Tầm nhìn là khoảng cách có thể nhìn rõ vật thể. Sương mù, mù, khói, bụi và mưa hoặc tuyết lớn có thể làm giảm tầm nhìn.',
          ),
        ),
        tomorrowCard(),
        InfoCard(
          icon: Icons.label_outline_rounded,
          title: tr(context, 'About the label', 'Về nhãn tầm nhìn'),
          body: tr(
            context,
            'Labels are an app category: under ${f.distanceU(1000)} very poor, ${f.distanceU(1000)}–${f.distanceU(5000)} limited, ${f.distanceU(5000)}–${f.distanceU(10000)} moderate, ${f.distanceU(10000)} or more good. They are not a driving or aviation safety standard.',
            'Nhãn là phân loại của ứng dụng: dưới ${f.distanceU(1000)} rất hạn chế, ${f.distanceU(1000)}–${f.distanceU(5000)} hạn chế, ${f.distanceU(5000)}–${f.distanceU(10000)} khá, từ ${f.distanceU(10000)} tốt. Đây không phải tiêu chuẩn an toàn khi lái xe hay bay.',
          ),
        ),
      ],
    );
  }

  static double _hazeFor(String? cat) => switch (cat) {
        'very_poor' => .85,
        'poor' => .6,
        'moderate' => .35,
        'good' => .1,
        _ => .3,
      };
}

/// Illustrative layered mountains with a haze veil (purely decorative).
class _MountainPainter extends CustomPainter {
  _MountainPainter({required this.haze});
  final double haze;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C3A73), Color(0xFF4A73B8), Color(0xFF9DB7E0)],
        ).createShader(rect),
    );
    void ridge(double base, List<double> peaks, Color color) {
      final path = Path()..moveTo(0, h);
      path.lineTo(0, h * base);
      for (var k = 0; k < peaks.length; k++) {
        final x = w * (k + 1) / (peaks.length + 1);
        final y = h * peaks[k];
        path.lineTo(x, y);
      }
      path.lineTo(w, h * base);
      path.lineTo(w, h);
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    ridge(.62, [.48, .58, .42, .55, .5], const Color(0xFF6A86BC));
    ridge(.74, [.62, .7, .58, .72], const Color(0xFF3E5D99));
    ridge(.86, [.78, .84, .76], const Color(0xFF1F3A6E));
    // Haze veil grows with poorer visibility.
    canvas.drawRect(
      Rect.fromLTWH(0, h * .35, w, h * .65),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: haze * .5)],
        ).createShader(Rect.fromLTWH(0, h * .35, w, h * .65)),
    );
    // Darken top so the white text stays readable.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h * .55),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: .35), Colors.black.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, w, h * .55)),
    );
  }

  @override
  bool shouldRepaint(_MountainPainter old) => old.haze != haze;
}
