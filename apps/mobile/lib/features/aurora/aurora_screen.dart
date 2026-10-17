import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/routes.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../metrics/charts_b.dart';

/// AUR01. Kp is a global index; the local outlook is qualitative and experimental.
/// The hemisphere switch only changes the viewing perspective, never the place.
class AuroraScreen extends StatefulWidget {
  const AuroraScreen({super.key, required this.location});
  final Location location;

  @override
  State<AuroraScreen> createState() => _AuroraScreenState();
}

class _AuroraScreenState extends State<AuroraScreen> {
  late String _hemi = widget.location.latitude < 0 ? 'south' : 'north';

  Future<void> _explore() async {
    final loc = await Routes.search(context);
    if (loc == null || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AuroraScreen(location: loc)));
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.location;
    return DetailScaffold(
      title: tr(context, 'Aurora forecast', 'Dự báo cực quang'),
      subtitle: loc.name,
      body: AsyncLoader<Json>(
        loadKey: _hemi,
        load: () => ApiClient.instance.aurora(loc.locationId, hemisphere: _hemi),
        builder: (context, json, reload) => _body(context, json, reload),
      ),
    );
  }

  Widget _body(BuildContext context, Json json, Future<void> Function() reload) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final loc = widget.location;
    final tz = loc.timezone;
    final kp = Section.parse(json['kp'], (v) => m(v)!);
    final night = Section.parse(json['night'], (v) => m(v)!);
    final outlook = m(json['localOutlook']);
    final cur = m(kp.data?['current']);
    final kpNow = d(cur?['kp']);
    final forecast = lm(kp.data?['forecast']);

    final kindLabel = switch (s(cur?['kind'])) {
      'observed' => tr(context, 'observed', 'quan trắc'),
      'estimated' => tr(context, 'estimated', 'ước tính'),
      'predicted' => tr(context, 'predicted', 'dự báo'),
      _ => null,
    };

    Color kpColor(double v) {
      if (v < 4) return const Color(0xFF3CCB7F);
      if (v < 5) return const Color(0xFFF5D547);
      if (v < 6) return const Color(0xFFFF9A3C);
      if (v < 7) return const Color(0xFFF2545B);
      return const Color(0xFF9B59D0);
    }

    final globe = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.4,
            child: CustomPaint(
              painter: _GlobePainter(
                south: _hemi == 'south',
                kp: kpNow,
                pinLat: loc.latitude,
                pinLon: loc.longitude,
                grid: c.cardBorder,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr(context, 'Illustration — not a live map. The oval only shows the typical aurora zone for the current Kp.',
                'Hình minh họa — không phải bản đồ trực tiếp. Vành chỉ thể hiện vùng cực quang điển hình theo Kp hiện tại.'),
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
        ],
      ),
    );

    final kpCard = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: tr(context, 'Current Kp', 'Kp hiện tại')),
          noticeFor(kp, onRetry: reload),
          if (kp.data != null) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ValueOrReason(
                  value: f.number(kpNow, digits: 1),
                  style: TextStyle(fontSize: 52, height: 1.1, fontWeight: FontWeight.w700, color: kpNow == null ? c.textPrimary : kpColor(kpNow)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      [
                        ?kindLabel,
                        if (cur?['time'] != null) '${tr(context, 'period from', 'khung từ')} ${f.time(s(cur?['time']), tz)}',
                      ].join(' · '),
                      style: TextStyle(color: c.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GradientScale(
              colors: const [Color(0xFF3CCB7F), Color(0xFFF5D547), Color(0xFFFF9A3C), Color(0xFFF2545B), Color(0xFF9B59D0)],
              position: kpNow == null ? null : kpNow / 9,
              ticks: [for (var k = 0; k <= 9; k++) '$k'],
            ),
            const SizedBox(height: 8),
            Text(tr(context, 'Kp is a global index, not a local value.', 'Kp là chỉ số toàn cầu, không phải giá trị tại địa phương.'),
                style: TextStyle(color: c.textMuted, fontSize: 12)),
          ],
          SourceFooter(source: kp.source, timezone: tz, stale: kp.isStale),
        ],
      ),
    );

    final forecastCard = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: tr(context, '3-hour Kp forecast', 'Dự báo Kp mỗi 3 giờ')),
          if (forecast.isEmpty)
            noticeFor(kp.data == null ? kp : Section<Json>(status: 'empty', reasonCode: 'NO_DATA', source: null, data: null))
          else ...[
            const SizedBox(height: 12),
            BarSeriesChart(
              values: [for (final e in forecast) d(e['kp'])],
              labels: [for (final e in forecast) s(e['time']) == null ? '' : f.hourOf(Fmt.local(s(e['time'])!, tz))],
              colorOf: kpColor,
              valueText: (v) => v.toStringAsFixed(1),
              labelEvery: forecast.length > 8 ? 2 : 1,
              minTop: 9,
              height: 160,
              semanticLabel: tr(context, 'Kp forecast chart', 'Biểu đồ dự báo Kp'),
            ),
            const SizedBox(height: 4),
            Text(tr(context, 'Times shown in the place\'s local time.', 'Giờ hiển thị theo giờ địa phương của địa điểm.'), style: TextStyle(color: c.textMuted, fontSize: 12)),
          ],
          SourceFooter(source: kp.source, timezone: tz, stale: kp.isStale),
        ],
      ),
    );

    final outlookValue = s(outlook?['value']);
    final (outTitle, outBody) = switch (outlookValue) {
      'possible' => (
          tr(context, 'Possible', 'Có thể thấy'),
          tr(context, 'With the current Kp, the aurora zone may reach this latitude. Dark, clear skies away from city lights are still needed.',
              'Với Kp hiện tại, vùng cực quang có thể tới vĩ độ này. Vẫn cần trời tối, quang mây và xa ánh đèn đô thị.'),
        ),
      'possible_high_latitude' => (
          tr(context, 'Only with strong activity', 'Chỉ khi hoạt động mạnh'),
          tr(context, 'This place is at a high latitude, but the aurora would need stronger activity than now to be overhead.',
              'Địa điểm ở vĩ độ cao, nhưng cần hoạt động mạnh hơn hiện tại để cực quang xuất hiện trên đầu.'),
        ),
      'unlikely' => (
          tr(context, 'Unlikely here', 'Khó thấy ở đây'),
          tr(context, 'This place is usually far from the aurora zone at the current Kp.', 'Địa điểm này thường ở xa vùng cực quang với Kp hiện tại.'),
        ),
      _ => (Fmt.dash, tr(context, 'Local outlook is not available.', 'Chưa có đánh giá tại địa phương.')),
    };

    final outlookCard = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(tr(context, 'Local outlook', 'Khả năng tại địa phương'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: c.textPrimary))),
              Pill(text: tr(context, 'Experimental', 'Thử nghiệm'), color: c.accent),
            ],
          ),
          const SizedBox(height: 8),
          Text(outTitle, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: c.textPrimary)),
          const SizedBox(height: 4),
          Text(outBody, style: TextStyle(color: c.textSecondary, height: 1.35)),
          const SizedBox(height: 8),
          Text(
            tr(context, 'A rough estimate from latitude and Kp only; not a probability. A high Kp does not guarantee a sighting.',
                'Ước lượng sơ bộ chỉ từ vĩ độ và Kp; không phải xác suất. Kp cao không đảm bảo nhìn thấy.'),
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
        ],
      ),
    );

    final nd = night.data;
    final cc = m(nd?['cloudCover']);
    final ccMin = Extremum.from(cc?['min']);
    final ccMax = Extremum.from(cc?['max']);
    final nightCard = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: tr(context, 'Tonight', 'Đêm nay'), icon: Icons.nights_stay_outlined),
          noticeFor(night, onRetry: reload),
          if (nd != null) ...[
            KeyValueRow(
              icon: Icons.dark_mode_outlined,
              label: tr(context, 'Dark window', 'Khung trời tối'),
              value: nd['darkFrom'] == null && nd['darkTo'] == null ? Fmt.dash : '${f.time(s(nd['darkFrom']), tz)} → ${f.time(s(nd['darkTo']), tz)}',
            ),
            KeyValueRow(
              icon: Icons.cloud_outlined,
              label: tr(context, 'Cloud cover tonight', 'Mây che phủ đêm nay'),
              value: ccMin == null || ccMax == null ? Fmt.dash : '${f.pct(ccMin.value)}–${f.pct(ccMax.value)}',
            ),
          ],
          SourceFooter(source: night.source, timezone: tz, stale: night.isStale),
        ],
      ),
    );

    return PageList(
      children: [
        PillTabs<String>(
          items: [
            ('north', tr(context, 'North', 'Bắc'), null),
            ('south', tr(context, 'South', 'Nam'), null),
          ],
          selected: _hemi,
          onChanged: (v) => setState(() => _hemi = v),
        ),
        Text(
          tr(context, 'Hemisphere changes the view only; the place stays the same.', 'Bán cầu chỉ đổi góc nhìn; địa điểm không đổi.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textMuted, fontSize: 12),
        ),
        globe,
        kpCard,
        outlookCard,
        forecastCard,
        nightCard,
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: c.accent,
            side: BorderSide(color: c.accent, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: _explore,
          icon: const Icon(Icons.travel_explore_rounded),
          label: Text(tr(context, 'Explore another location', 'Xem địa điểm khác'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        AlertsUnavailableCard(
          title: tr(context, 'Aurora alerts', 'Cảnh báo cực quang'),
          message: tr(context, 'Aurora notifications are not available yet.', 'Thông báo cực quang chưa được hỗ trợ.'),
        ),
      ],
    );
  }
}

/// Stylised polar view of one hemisphere (azimuthal, pole at centre, equator at the rim).
/// The oval is centred near the geomagnetic pole and sized from Kp — illustrative only.
class _GlobePainter extends CustomPainter {
  _GlobePainter({required this.south, required this.kp, required this.pinLat, required this.pinLon, required this.grid});
  final bool south;
  final double? kp;
  final double pinLat;
  final double pinLon;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 4;
    final globe = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()..shader = const RadialGradient(colors: [Color(0xFF1C3A73), Color(0xFF0A1830)]).createShader(globe),
    );

    // Point for (lat, lon) in this hemisphere's projection.
    Offset project(double lat, double lon) {
      final colat = 90 - (south ? -lat : lat);
      final rr = r * colat / 90;
      // North view: longitude increases counter-clockwise; south view mirrored.
      final a = (south ? 1 : -1) * lon * math.pi / 180 + math.pi / 2;
      return center + Offset(math.cos(a), math.sin(a)) * rr;
    }

    final gridPaint = Paint()
      ..color = grid.withValues(alpha: .8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final lat in [30.0, 60.0]) {
      canvas.drawCircle(center, r * (90 - lat) / 90, gridPaint);
    }
    for (var lon = 0; lon < 360; lon += 45) {
      canvas.drawLine(center, project(0, lon.toDouble()), gridPaint);
    }
    canvas.drawCircle(center, r, gridPaint);

    // Aurora oval: geomagnetic pole ~80.7°N 72.7°W / 80.7°S 107.3°E (approximate).
    if (kp != null) {
      final pole = south ? project(-80.7, 107.3) : project(80.7, -72.7);
      final colat = (20 + kp!.clamp(0, 9) * 2.2) / 90 * r;
      final oval = Rect.fromCircle(center: pole, radius: colat);
      canvas.drawCircle(
        pole,
        colat,
        Paint()
          ..color = const Color(0x552EE59D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * .14
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawOval(
        oval,
        Paint()
          ..color = const Color(0xCC2EE59D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    // The place's pin, only if it is in the viewed hemisphere. No aurora is drawn around it.
    final inView = south ? pinLat < 0 : pinLat >= 0;
    if (inView) {
      final p = project(pinLat, pinLon);
      canvas.drawCircle(p, 7, Paint()..color = Colors.white);
      canvas.drawCircle(p, 4, Paint()..color = const Color(0xFFF58A6E));
    }
  }

  @override
  bool shouldRepaint(_GlobePainter old) => old.south != south || old.kp != kp || old.pinLat != pinLat || old.pinLon != pinLon;
}
