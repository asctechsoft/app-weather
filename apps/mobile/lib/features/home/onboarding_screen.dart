import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/routes.dart';
import '../../ui/theme.dart';
import '../../ui/weather_icon.dart';
import '../../ui/widgets.dart';
import 'home_controller.dart';

/// First launch (no valid default): choose GPS or search a city.
/// Location permission is requested only after the user taps "Use current location";
/// Hanoi (or any city) is never assumed.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.controller, required this.onReady});
  final HomeController controller;
  final ValueChanged<Location> onReady;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool busy = false;
  String? message;

  Future<void> _useGps() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'Use your location?', 'Dùng vị trí của bạn?')),
        content: Text(tr(
          context,
          'SkyWeather uses your position only to fetch weather for where you are. It is not used for tracking, and you can still search cities manually.',
          'SkyWeather chỉ dùng vị trí để lấy thời tiết nơi bạn đang ở, không dùng để theo dõi. Bạn vẫn có thể tìm thành phố thủ công.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'Not now', 'Để sau'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'Continue', 'Tiếp tục'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      busy = true;
      message = null;
    });
    final (res, loc) = await widget.controller.locate();
    if (!mounted) return;
    setState(() => busy = false);
    if (res == GpsResult.ok && loc != null) {
      widget.onReady(loc);
      return;
    }
    setState(() {
      message = switch (res) {
        GpsResult.serviceOff => tr(context, 'Location services are off. Turn them on or search for a city.', 'Dịch vụ vị trí đang tắt. Hãy bật hoặc tìm thành phố.'),
        GpsResult.denied => tr(context, 'Location permission was not granted. You can search for a city instead.', 'Chưa được cấp quyền vị trí. Bạn có thể tìm thành phố thay thế.'),
        GpsResult.deniedForever => tr(context, 'Location is blocked in device settings. Search for a city, or allow location in Settings.', 'Vị trí bị chặn trong cài đặt thiết bị. Hãy tìm thành phố hoặc cho phép trong Cài đặt.'),
        GpsResult.timeout => tr(context, 'Could not get a position in time. Try again or search for a city.', 'Không lấy được vị trí kịp thời. Thử lại hoặc tìm thành phố.'),
        GpsResult.serverError => tr(context, 'Could not resolve this position on the server. Try again or search.', 'Máy chủ không xác định được vị trí này. Thử lại hoặc tìm kiếm.'),
        GpsResult.ok => null,
      };
    });
  }

  Future<void> _search() async {
    final loc = await Routes.search(context);
    if (loc != null && mounted) widget.onReady(loc);
  }

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const WeatherIcon(code: 'PARTLY_CLOUDY', isDay: true, size: 120),
                    const SizedBox(height: 12),
                    Text('SkyWeather', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: c.textPrimary)),
                    const SizedBox(height: 8),
                    Text(
                      tr(context, 'Choose where to see the weather first. You can add more places later.', 'Chọn nơi bạn muốn xem thời tiết. Bạn có thể thêm địa điểm khác sau.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textSecondary, fontSize: 16, height: 1.4),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: const Color(0xFF2A0F08), padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: busy ? null : _useGps,
                        icon: busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.near_me_rounded),
                        label: Text(tr(context, 'Use current location', 'Dùng vị trí hiện tại'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: c.textPrimary, side: BorderSide(color: c.cardBorder), padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: busy ? null : _search,
                        icon: const Icon(Icons.search_rounded),
                        label: Text(tr(context, 'Search for a city', 'Tìm thành phố'), style: const TextStyle(fontSize: 17)),
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 18),
                      Text(message!, textAlign: TextAlign.center, style: TextStyle(color: c.accent)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
