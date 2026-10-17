import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../ui/theme.dart';
import '../../ui/weather_icon.dart';
import '../../ui/widgets.dart';
import 'settings_screen.dart';

/// APPEAR01. Draft + Save changes; theme does not touch units or places.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late AppearancePrefs _saved;
  late AppearancePrefs _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _saved = SettingsScope.read(context).appearance;
    _draft = _saved;
  }

  bool get _dirty =>
      _draft.theme != _saved.theme || _draft.weatherBackground != _saved.weatherBackground || _draft.reduceMotion != _saved.reduceMotion;

  Future<void> _save() async {
    setState(() => _saving = true);
    await SettingsScope.read(context).setAppearance(_draft);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return DraftGuard(
      dirty: _dirty && !_saving,
      child: DetailScaffold(
        title: tr(context, 'Appearance', 'Giao diện'),
        centerTitle: false,
        body: BodyWithAction(
          action: PrimaryButton(label: tr(context, 'Save changes', 'Lưu thay đổi'), busy: _saving, onPressed: _dirty ? _save : null),
          children: [
            _ThemePreview(prefs: _draft),
            SegmentedSetting<String>(
              icon: Icons.dark_mode_outlined,
              title: tr(context, 'Theme', 'Chủ đề'),
              items: [('light', tr(context, 'Light', 'Sáng')), ('dark', tr(context, 'Dark', 'Tối')), ('system', tr(context, 'System', 'Hệ thống'))],
              selected: _draft.theme,
              onChanged: (v) => setState(() => _draft = _draft.copyWith(theme: v)),
            ),
            if (_draft.theme == 'system')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(tr(context, 'Follows your device setting and changes when it changes.', 'Theo cài đặt của thiết bị và tự đổi khi thiết bị đổi.'),
                    style: TextStyle(color: c.textSecondary, fontSize: 13)),
              ),
            SettingsGroup(
              children: [
                SettingsSwitchRow(
                  icon: Icons.wallpaper_rounded,
                  title: tr(context, 'Weather background', 'Nền theo thời tiết'),
                  subtitle: tr(context, 'Background follows the condition and day/night. Off uses the plain theme background.',
                      'Nền thay theo thời tiết và ngày/đêm. Tắt sẽ dùng nền tĩnh của chủ đề.'),
                  value: _draft.weatherBackground,
                  onChanged: (v) => setState(() => _draft = _draft.copyWith(weatherBackground: v)),
                ),
                SettingsSwitchRow(
                  icon: Icons.motion_photos_off_outlined,
                  title: tr(context, 'Reduce motion', 'Giảm chuyển động'),
                  subtitle: tr(context, 'Turns off cloud, rain and arc animations. Data and actions stay the same.',
                      'Tắt hiệu ứng mây, mưa và cung mặt trời. Dữ liệu và thao tác không thay đổi.'),
                  value: _draft.reduceMotion,
                  onChanged: (v) => setState(() => _draft = _draft.copyWith(reduceMotion: v)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.prefs});
  final AppearancePrefs prefs;

  @override
  Widget build(BuildContext context) {
    final brightness = switch (prefs.theme) {
      'light' => Brightness.light,
      'dark' => Brightness.dark,
      _ => MediaQuery.platformBrightnessOf(context),
    };
    final p = brightness == Brightness.dark ? SkyColors.dark : SkyColors.light;
    final bg = prefs.weatherBackground
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: brightness == Brightness.dark ? const [Color(0xFF2A4F8F), Color(0xFF0C1E3D)] : const [Color(0xFF8FB8F5), Color(0xFFE6EEFB)],
          )
        : LinearGradient(colors: [p.bgBottom, p.bgBottom]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Eyebrow(tr(context, 'Preview', 'Xem trước'))),
        Container(
          height: 150,
          decoration: BoxDecoration(gradient: bg, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.cardBorder)),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const WeatherIcon(code: 'PARTLY_CLOUDY', isDay: true, size: 72),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(tr(context, 'Sample place', 'Địa điểm mẫu'), style: TextStyle(color: p.textSecondary, fontSize: 14)),
                    Text('--°', style: TextStyle(color: p.textPrimary, fontSize: 44, fontWeight: FontWeight.w300)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.cardBorder)),
                      child: Text(conditionLabel(context, 'PARTLY_CLOUDY', isDay: true), style: TextStyle(color: p.textPrimary, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
