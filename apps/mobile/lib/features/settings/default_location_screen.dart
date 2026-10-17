import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../ui/routes.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'settings_screen.dart';

/// DEFAULT01. One radio (draft) → Save sets defaultMode gps|saved. Never deletes or reorders places.
class DefaultLocationScreen extends StatefulWidget {
  const DefaultLocationScreen({super.key});

  @override
  State<DefaultLocationScreen> createState() => _DefaultLocationScreenState();
}

class _DefaultLocationScreenState extends State<DefaultLocationScreen> {
  String? _savedMode;
  String? _savedId;
  String? _mode;
  String? _id;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = SettingsScope.read(context);
    _savedMode = s.defaultMode;
    _savedId = s.defaultMode == 'saved' ? s.defaultLocationId : null;
    _mode = _savedMode;
    _id = _savedId;
  }

  bool get _dirty => _mode != _savedMode || _id != _savedId;

  bool _valid(AppSettings s) => (_mode == 'gps' && s.gpsEnabled) || (_mode == 'saved' && _id != null && s.isSaved(_id!));

  Future<void> _save() async {
    final s = SettingsScope.read(context);
    setState(() => _saving = true);
    await s.setDefault(mode: _mode!, locationId: _id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _searchAndAdd() async {
    final loc = await Routes.search(context);
    if (!mounted || loc == null) return;
    final s = SettingsScope.read(context);
    if (s.isSaved(loc.locationId)) {
      setState(() {
        _mode = 'saved';
        _id = loc.locationId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final c = SkyColors.of(context);
    final gps = s.gpsLocation;

    return DraftGuard(
      dirty: _dirty && !_saving,
      child: DetailScaffold(
        title: tr(context, 'Default location', 'Vị trí mặc định'),
        centerTitle: false,
        body: BodyWithAction(
          action: PrimaryButton(
            label: tr(context, 'Save', 'Lưu'),
            busy: _saving,
            onPressed: _dirty && _valid(s) ? _save : null,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                tr(context, 'SkyWeather opens on this place.', 'SkyWeather sẽ mở tại địa điểm này.'),
                style: TextStyle(color: c.textSecondary),
              ),
            ),
            SettingsGroup(
              children: [
                ChoiceRow(
                  leading: Icon(Icons.near_me_outlined, color: s.gpsEnabled ? c.blue : c.textMuted),
                  title: tr(context, 'Current location', 'Vị trí hiện tại'),
                  subtitle: s.gpsEnabled
                      ? (gps?.name != null ? '${tr(context, 'Last known', 'Gần nhất')}: ${gps!.name}' : null)
                      : tr(context, 'Turn on "Use current location" in Manage places first.',
                          'Hãy bật "Dùng vị trí hiện tại" trong Quản lý địa điểm trước.'),
                  selected: _mode == 'gps',
                  onTap: s.gpsEnabled
                      ? () => setState(() {
                            _mode = 'gps';
                            _id = null;
                          })
                      : null,
                ),
                for (final p in s.savedPlaces)
                  ChoiceRow(
                    leading: Icon(Icons.place_outlined, color: c.textSecondary),
                    title: placeTitle(context, p),
                    subtitle: placeSubtitle(p).isEmpty ? null : placeSubtitle(p),
                    selected: _mode == 'saved' && _id == p.locationId,
                    onTap: () => setState(() {
                      _mode = 'saved';
                      _id = p.locationId;
                    }),
                  ),
              ],
            ),
            if (!s.gpsEnabled)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Routes.places(context),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(tr(context, 'Open Manage places', 'Mở Quản lý địa điểm')),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _searchAndAdd,
              icon: const Icon(Icons.search_rounded),
              label: Text(tr(context, 'Search or add place', 'Tìm hoặc thêm địa điểm')),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.textPrimary,
                side: BorderSide(color: c.cardBorder),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
            ),
            if (s.savedPlaces.isEmpty && !s.gpsEnabled)
              Text(
                tr(context, 'No places yet. Add a place or turn on current location.', 'Chưa có địa điểm. Hãy thêm địa điểm hoặc bật vị trí hiện tại.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
