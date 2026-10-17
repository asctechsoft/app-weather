import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../settings/notifications_screen.dart';
import '../settings/settings_screen.dart';

/// ALERT01. GET /v1/alerts currently answers unsupported / COVERAGE_NOT_VERIFIED.
/// "Unsupported" is shown differently from "no active alerts" and never implies "no risk".
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key, required this.location});
  final Location location;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String _tab = 'active';

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return DetailScaffold(
      title: tr(context, 'Weather alerts', 'Cảnh báo thời tiết'),
      subtitle: placeTitle(context, widget.location),
      body: PageList(
        children: [
          PillTabs<String>(
            items: [
              ('active', tr(context, 'Active', 'Đang hiệu lực'), null),
              ('past', tr(context, 'Past', 'Đã qua'), null),
            ],
            selected: _tab,
            onChanged: (v) => setState(() => _tab = v),
          ),
          GlassCard(
            child: UnsupportedView(
              icon: Icons.gpp_maybe_outlined,
              title: _tab == 'active'
                  ? tr(context, 'Official alerts not available here yet', 'Chưa có cảnh báo chính thức tại đây')
                  : tr(context, 'No alert history', 'Chưa có lịch sử cảnh báo'),
              message: _tab == 'active'
                  ? tr(context,
                      'No verified official alert source covers this area yet — this does not mean there is no risk. Follow your national weather service and local authorities.',
                      'Chưa có nguồn cảnh báo chính thức được xác minh cho khu vực này — điều đó không có nghĩa là không có rủi ro. Hãy theo dõi cơ quan khí tượng quốc gia và chính quyền địa phương.')
                  : tr(context,
                      'Alert history starts only after a verified source is connected for this area. Nothing has been collected yet.',
                      'Lịch sử cảnh báo chỉ bắt đầu sau khi có nguồn được xác minh cho khu vực này. Hiện chưa thu thập gì.'),
            ),
          ),
          GlassCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded, color: c.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(context, 'SkyWeather reminders', 'Nhắc nhở từ SkyWeather'),
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.textPrimary)),
                      const SizedBox(height: 6),
                      Text(
                        tr(context,
                            'UV, rain and air-quality reminders appear in Weather insights on Home. They are calculated from forecast data and are not official warnings.',
                            'Nhắc nhở UV, mưa và chất lượng không khí hiển thị trong Weather insights ở trang chủ. Chúng được tính từ dữ liệu dự báo và không phải cảnh báo chính thức.'),
                        style: TextStyle(color: c.textSecondary, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => pushPage(context, const NotificationsScreen()),
            icon: const Icon(Icons.notifications_none_rounded),
            label: Text(tr(context, 'Notification preferences', 'Tùy chọn thông báo')),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.textPrimary,
              side: BorderSide(color: c.cardBorder),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            ),
          ),
        ],
      ),
    );
  }
}
