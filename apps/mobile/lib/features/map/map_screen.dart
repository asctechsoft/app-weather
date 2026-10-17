import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/routes.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// MAP01. The server reports MAP_PROVIDER_NOT_CONFIGURED, so there is no map, no fake radar
/// and no hard-coded timeline — only an honest explanation for the current place.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key, required this.location});
  final Location location;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final name = location.name ?? (location.isGps ? tr(context, 'Current location', 'Vị trí hiện tại') : '-');
    return DetailScaffold(
      title: tr(context, 'Weather map', 'Bản đồ thời tiết'),
      subtitle: name,
      body: PageList(
        children: [
          GlassCard(
            child: UnsupportedView(
              icon: Icons.layers_clear_outlined,
              title: tr(context, 'Weather map not available yet', 'Chưa có bản đồ thời tiết'),
              message: tr(
                context,
                'Forecast map layers (rain, temperature, wind) need a licensed map and tile source, which is not configured for this build. No radar or forecast frames are shown until a verified source is connected.',
                'Các lớp bản đồ dự báo (mưa, nhiệt độ, gió) cần nguồn bản đồ và tile có giấy phép, bản build này chưa cấu hình. Sẽ không hiển thị radar hay khung dự báo nào cho đến khi có nguồn được xác minh.',
              ),
            ),
          ),
          GlassCard(
            child: Row(
              children: [
                Icon(Icons.place_outlined, color: c.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$name · ${location.latitude.toStringAsFixed(2)}, ${location.longitude.toStringAsFixed(2)}',
                    style: TextStyle(color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => Routes.hourly(context, location, metric: 'rain'),
            icon: const Icon(Icons.umbrella_outlined),
            label: Text(tr(context, 'See hourly rain forecast', 'Xem dự báo mưa theo giờ')),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.textPrimary,
              side: BorderSide(color: c.cardBorder),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            ),
          ),
          TextButton(
            onPressed: () => Routes.dataSources(context, location),
            child: Text(tr(context, 'Weather data & attribution', 'Dữ liệu thời tiết & ghi nguồn')),
          ),
        ],
      ),
    );
  }
}
