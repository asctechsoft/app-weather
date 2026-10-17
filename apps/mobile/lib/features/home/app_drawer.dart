import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../ui/routes.dart';
import '../../ui/theme.dart';
import '../../ui/weather_icon.dart';
import 'home_controller.dart';

/// DRAWER01 — every item opens a real route for the active place.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.controller});
  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final f = Fmt.of(context);
    final loc = controller.active!;
    final cur = controller.snapshot?.current.data;

    void go(void Function() open) {
      Navigator.of(context).pop();
      open();
    }

    Widget item(IconData icon, String label, VoidCallback onTap) => ListTile(
          leading: Icon(icon, color: c.textSecondary, size: 26),
          title: Text(label, style: TextStyle(fontSize: 18, color: c.textPrimary)),
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        );

    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
          child: Text(t.toUpperCase(), style: TextStyle(letterSpacing: 2.5, color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        );

    return Drawer(
      backgroundColor: c.bgTop,
      width: MediaQuery.sizeOf(context).width * .78 > 340 ? 340 : MediaQuery.sizeOf(context).width * .78,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const WeatherIcon(code: 'MOSTLY_CLEAR', isDay: true, size: 44),
                  const SizedBox(width: 12),
                  Expanded(child: Text('SkyWeather', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.textPrimary))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: c.textPrimary), tooltip: tr(context, 'Close', 'Đóng')),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: c.cardBorder), color: c.card),
              child: Row(
                children: [
                  Icon(loc.isGps ? Icons.near_me_outlined : Icons.place_outlined, color: c.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(loc.name ?? tr(context, 'Current location', 'Vị trí hiện tại'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, color: c.textPrimary)),
                        Text(loc.country ?? '', style: TextStyle(color: c.textSecondary)),
                      ],
                    ),
                  ),
                  if (cur != null) WeatherIcon(code: cur.conditionCode, isDay: cur.isDay, size: 36),
                  const SizedBox(width: 6),
                  Text(f.deg(cur?.temperatureC), style: TextStyle(fontSize: 30, color: c.accent, fontWeight: FontWeight.w300)),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: c.accent), color: c.accentSoft),
              child: ListTile(
                leading: Icon(Icons.home_outlined, color: c.accent),
                title: Text(tr(context, 'Today', 'Hôm nay'), style: TextStyle(color: c.accent, fontSize: 18, fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(context),
              ),
            ),
            item(Icons.place_outlined, tr(context, 'Manage places', 'Quản lý địa điểm'), () => go(() => Routes.places(context))),
            Divider(color: c.divider, indent: 20, endIndent: 20),
            header(tr(context, 'Weather', 'Thời tiết')),
            item(Icons.schedule_rounded, tr(context, 'Hourly forecast', 'Dự báo theo giờ'), () => go(() => Routes.hourly(context, loc))),
            item(Icons.calendar_month_outlined, tr(context, '10-day outlook', 'Dự báo 10 ngày'), () => go(() => Routes.daily(context, loc))),
            item(Icons.map_outlined, tr(context, 'Weather map', 'Bản đồ thời tiết'), () => go(() => Routes.map(context, loc))),
            item(Icons.notifications_none_rounded, tr(context, 'Weather alerts', 'Cảnh báo thời tiết'), () => go(() => Routes.alerts(context, loc))),
            item(Icons.eco_outlined, tr(context, 'Air quality', 'Chất lượng không khí'), () => go(() => Routes.airQuality(context, loc))),
            item(Icons.wb_sunny_outlined, tr(context, 'Sun & moon', 'Mặt trời & mặt trăng'), () => go(() => Routes.sunMoon(context, loc))),
            item(Icons.waves_rounded, tr(context, 'Aurora forecast', 'Dự báo cực quang'), () => go(() => Routes.aurora(context, loc))),
            Divider(color: c.divider, indent: 20, endIndent: 20),
            header(tr(context, 'App', 'Ứng dụng')),
            item(Icons.grid_view_rounded, tr(context, 'Customize Home', 'Tùy chỉnh trang chủ'), () => go(() => Routes.customizeHome(context))),
            item(Icons.widgets_outlined, tr(context, 'Widgets', 'Widget'), () => go(() => Routes.widgets(context))),
            item(Icons.settings_outlined, tr(context, 'Settings', 'Cài đặt'), () => go(() => Routes.settings(context))),
            Divider(color: c.divider, indent: 20, endIndent: 20),
            item(Icons.info_outline_rounded, tr(context, 'Weather data & attribution', 'Dữ liệu thời tiết & ghi nguồn'), () => go(() => Routes.dataSources(context, loc))),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snap) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  snap.hasData ? '${tr(context, 'Version', 'Phiên bản')} ${snap.data!.version} (${snap.data!.buildNumber})' : '',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.blue),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
