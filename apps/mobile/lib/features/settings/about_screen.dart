import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/l10n.dart';
import '../../ui/routes.dart';
import '../../ui/theme.dart';
import '../../ui/weather_icon.dart';
import '../../ui/widgets.dart';
import 'feedback_screen.dart';
import 'settings_screen.dart';

/// About (SET01): version/build from the platform, never hard-coded.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return DetailScaffold(
      title: tr(context, 'About', 'Giới thiệu'),
      centerTitle: false,
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          final info = snap.data;
          return PageList(
            children: [
              Column(
                children: [
                  const SizedBox(height: 8),
                  const WeatherIcon(code: 'MOSTLY_CLEAR', isDay: true, size: 72),
                  const SizedBox(height: 8),
                  Text(info?.appName.isNotEmpty == true ? info!.appName : 'SkyWeather',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.textPrimary)),
                  Text(tr(context, 'Global weather forecast', 'Dự báo thời tiết toàn cầu'), style: TextStyle(color: c.textSecondary)),
                ],
              ),
              SettingsGroup(
                children: [
                  SettingsRow(icon: Icons.tag_rounded, title: tr(context, 'Version', 'Phiên bản'), value: info?.version ?? '-'),
                  SettingsRow(icon: Icons.build_outlined, title: tr(context, 'Build', 'Bản build'), value: info?.buildNumber ?? '-'),
                  SettingsRow(icon: Icons.dns_outlined, title: tr(context, 'Environment', 'Môi trường'), value: AppConfig.appEnv),
                  SettingsRow(
                    icon: Icons.link_rounded,
                    title: tr(context, 'Weather server', 'Máy chủ thời tiết'),
                    subtitle: AppConfig.apiBaseUrl,
                  ),
                ],
              ),
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: Icons.bar_chart_rounded,
                    title: tr(context, 'Weather data & attribution', 'Dữ liệu thời tiết & ghi nguồn'),
                    onTap: () => Routes.dataSources(context, null),
                  ),
                  SettingsRow(
                    icon: Icons.support_agent_rounded,
                    title: tr(context, 'Support', 'Hỗ trợ'),
                    subtitle: tr(context, 'Questions or problems? Send us feedback from the app.', 'Có câu hỏi hoặc sự cố? Hãy gửi góp ý ngay trong ứng dụng.'),
                    onTap: () => pushPage(context, const FeedbackScreen()),
                  ),
                ],
              ),
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: Icons.delete_outline_rounded,
                    title: tr(context, 'Delete my data on the server', 'Xóa dữ liệu của tôi trên máy chủ'),
                    subtitle: tr(context, 'Revokes this installation and deletes its server-side data. Places and settings on this device are kept.',
                        'Thu hồi installation này và xóa dữ liệu phía máy chủ. Địa điểm và cài đặt trên máy vẫn được giữ.'),
                    onTap: () => _confirmDelete(context),
                  ),
                ],
              ),
              Text(
                tr(context, 'Forecasts are model data and can differ from local observations. SkyWeather does not issue official warnings.',
                    'Dự báo là dữ liệu mô hình và có thể khác quan trắc tại chỗ. SkyWeather không phát hành cảnh báo chính thức.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
            ],
          );
        },
      ),
    );
  }

  /// SW081: server-side deletion. The app registers a fresh anonymous installation on the next request.
  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'Delete server data?', 'Xóa dữ liệu trên máy chủ?')),
        content: Text(tr(context, 'Feedback tickets you sent are kept for their published retention period but are no longer linked to this device.',
            'Các góp ý đã gửi được giữ theo thời hạn lưu trữ đã công bố nhưng không còn gắn với thiết bị này.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'Cancel', 'Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'Delete', 'Xóa'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final done = tr(context, 'Server data deleted.', 'Đã xóa dữ liệu trên máy chủ.');
    try {
      await ApiClient.instance.deleteInstallation();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (context.mounted) messenger.showSnackBar(SnackBar(content: Text(errorText(context, e))));
    }
  }
}
