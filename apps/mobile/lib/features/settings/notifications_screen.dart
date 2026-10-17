import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// NOTI01. Push is not available in this build (config features.push = false),
/// so there are no switches that would pretend to schedule anything.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final planned = <(IconData, String)>[
      (Icons.warning_amber_rounded, tr(context, 'Severe weather (official alerts)', 'Thời tiết nguy hiểm (cảnh báo chính thức)')),
      (Icons.umbrella_outlined, tr(context, 'Rain starting soon', 'Sắp có mưa')),
      (Icons.wb_sunny_outlined, tr(context, 'High UV', 'UV cao')),
      (Icons.eco_outlined, tr(context, 'Air quality (AQI)', 'Chất lượng không khí (AQI)')),
      (Icons.today_outlined, tr(context, 'Daily forecast', 'Dự báo hằng ngày')),
      (Icons.waves_rounded, tr(context, 'Aurora', 'Cực quang')),
    ];

    return DetailScaffold(
      title: tr(context, 'Notifications', 'Thông báo'),
      centerTitle: false,
      body: PageList(
        children: [
          UnsupportedView(
            icon: Icons.notifications_off_outlined,
            title: tr(context, 'Notifications are not available yet', 'Chưa hỗ trợ thông báo'),
            message: tr(
              context,
              'This build does not include push notifications. Nothing will be sent to your device now, and SkyWeather does not ask for notification permission.',
              'Bản build này chưa có thông báo đẩy. Hiện sẽ không có thông báo nào được gửi tới thiết bị và SkyWeather không xin quyền thông báo.',
            ),
          ),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(tr(context, 'Planned', 'Dự kiến')),
                const SizedBox(height: 10),
                for (final (icon, label) in planned)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(icon, size: 22, color: c.textSecondary),
                        const SizedBox(width: 12),
                        Expanded(child: Text(label, style: TextStyle(color: c.textPrimary, fontSize: 16))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          InfoCard(
            title: tr(context, 'Reminders on Home', 'Nhắc nhở trên trang chủ'),
            body: tr(
              context,
              'UV, rain and air quality reminders are shown in Weather insights on Home. They are SkyWeather reminders, not official warnings.',
              'Nhắc nhở UV, mưa và chất lượng không khí hiển thị trong mục Weather insights ở trang chủ. Đây là nhắc nhở của SkyWeather, không phải cảnh báo chính thức.',
            ),
          ),
        ],
      ),
    );
  }
}
