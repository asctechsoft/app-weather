import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../ui/theme.dart';
import '../../ui/weather_icon.dart';
import '../../ui/widgets.dart';
import 'settings_screen.dart';

/// UNIT01. Works on a draft; Reset only changes the draft; Save applies everywhere.
class UnitsScreen extends StatefulWidget {
  const UnitsScreen({super.key});

  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen> {
  late UnitPrefs _saved;
  late UnitPrefs _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _saved = SettingsScope.read(context).units;
    _draft = _saved;
  }

  bool get _dirty => _draft != _saved;

  Future<void> _save() async {
    setState(() => _saving = true);
    await SettingsScope.read(context).setUnits(_draft);
    if (!mounted) return;
    _saved = _draft;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final lang = SettingsScope.of(context).effectiveLanguage;
    final f = Fmt(_draft, lang);

    return DraftGuard(
      dirty: _dirty && !_saving,
      child: DetailScaffold(
        title: tr(context, 'Units', 'Đơn vị'),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: _draft == UnitPrefs.defaults ? null : () => setState(() => _draft = UnitPrefs.defaults),
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(tr(context, 'Reset', 'Đặt lại')),
            style: TextButton.styleFrom(foregroundColor: c.textPrimary),
          ),
        ],
        body: BodyWithAction(
          action: PrimaryButton(label: tr(context, 'Save', 'Lưu'), busy: _saving, onPressed: _dirty ? _save : null),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(tr(context, 'Choose how weather measurements appear', 'Chọn cách hiển thị các số đo thời tiết'),
                  style: TextStyle(fontSize: 16, color: c.textSecondary)),
            ),
            SegmentedSetting<String>(
              icon: Icons.thermostat_rounded,
              title: tr(context, 'Temperature', 'Nhiệt độ'),
              items: const [('c', '°C'), ('f', '°F')],
              selected: _draft.temperature,
              onChanged: (v) => setState(() => _draft = _draft.copyWith(temperature: v)),
            ),
            SegmentedSetting<String>(
              icon: Icons.air_rounded,
              title: tr(context, 'Wind speed', 'Tốc độ gió'),
              items: [('kmh', 'km/h'), ('ms', 'm/s'), ('mph', 'mph'), ('kn', tr(context, 'knots', 'hải lý'))],
              selected: _draft.wind,
              onChanged: (v) => setState(() => _draft = _draft.copyWith(wind: v)),
            ),
            SegmentedSetting<String>(
              icon: Icons.water_drop_outlined,
              title: tr(context, 'Precipitation', 'Lượng mưa'),
              items: const [('mm', 'mm'), ('in', 'in')],
              selected: _draft.precipitation,
              onChanged: (v) => setState(() => _draft = _draft.copyWith(precipitation: v)),
            ),
            SegmentedSetting<String>(
              icon: Icons.speed_rounded,
              title: tr(context, 'Pressure', 'Áp suất'),
              items: const [('hpa', 'hPa'), ('inhg', 'inHg'), ('mmhg', 'mmHg')],
              selected: _draft.pressure,
              onChanged: (v) => setState(() => _draft = _draft.copyWith(pressure: v)),
            ),
            SegmentedSetting<String>(
              icon: Icons.visibility_outlined,
              title: tr(context, 'Visibility', 'Tầm nhìn'),
              items: const [('km', 'km'), ('mi', 'mi')],
              selected: _draft.distance,
              onChanged: (v) => setState(() => _draft = _draft.copyWith(distance: v)),
            ),
            SegmentedSetting<String>(
              icon: Icons.schedule_rounded,
              title: tr(context, 'Time format', 'Định dạng giờ'),
              items: [('12', tr(context, '12-hour', '12 giờ')), ('24', tr(context, '24-hour', '24 giờ'))],
              selected: _draft.timeFormat,
              onChanged: (v) => setState(() => _draft = _draft.copyWith(timeFormat: v)),
            ),
            _Preview(f: f),
          ],
        ),
      ),
    );
  }
}

/// Fixed canonical sample values (clearly labelled as samples) converted with the draft units.
class _Preview extends StatelessWidget {
  const _Preview({required this.f});
  final Fmt f;

  static const _sampleTempC = 26.0;
  static const _sampleWindMs = 3.06;
  static const _samplePrecipMm = 0.0;
  static const _samplePressureHpa = 1013.0;
  static const _sampleVisibilityM = 10000.0;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    Widget cell(Widget icon, String value) => Expanded(
          child: Column(
            children: [
              SizedBox(height: 40, child: Center(child: icon)),
              const SizedBox(height: 8),
              FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 24, color: c.textPrimary))),
            ],
          ),
        );
    Widget sep() => Container(width: 1, height: 56, color: c.divider);
    final sampleTime = DateTime(2000, 1, 1, 15, 30);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(tr(context, 'Preview', 'Xem trước')),
          const SizedBox(height: 4),
          Text(tr(context, 'Sample values — not live weather', 'Giá trị mẫu — không phải thời tiết thực'), style: TextStyle(color: c.textSecondary)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: c.cardBorder)),
            child: Column(
              children: [
                Row(
                  children: [
                    cell(const WeatherIcon(code: 'MOSTLY_CLEAR', isDay: true, size: 40), f.degU(_sampleTempC)),
                    sep(),
                    cell(Icon(Icons.air_rounded, color: c.textSecondary, size: 30), f.windU(_sampleWindMs)),
                    sep(),
                    cell(Icon(Icons.water_drop_outlined, color: c.textSecondary, size: 30), f.precipU(_samplePrecipMm)),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    Text('${tr(context, 'Pressure', 'Áp suất')} ${f.pressureU(_samplePressureHpa)}', style: TextStyle(color: c.textSecondary)),
                    Text('${tr(context, 'Visibility', 'Tầm nhìn')} ${f.distanceU(_sampleVisibilityM)}', style: TextStyle(color: c.textSecondary)),
                    Text('${tr(context, 'Time', 'Giờ')} ${f.timeOf(sampleTime)}', style: TextStyle(color: c.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
