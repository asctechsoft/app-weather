import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../ui/routes.dart';
import '../../ui/theme.dart';
import '../../ui/weather_icon.dart';
import '../../ui/widgets.dart';
import '../settings/settings_screen.dart';

/// Opens the weather preview for a search result (PLACE01).
/// Returns the [Location] when it was added (or was already saved and the user chose Open);
/// null when dismissed or when the list is full and the user went to Manage places.
Future<Location?> showPlacePreview(BuildContext context, Location loc) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => PlacePreviewSheet(location: loc),
  );
  if (!context.mounted || action == null) return null;
  final settings = SettingsScope.read(context);
  switch (action) {
    case 'open':
      return loc;
    case 'add':
      final ok = await settings.addPlace(loc);
      if (!context.mounted) return null;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(context, 'Your list is full (${AppConfig.savedPlacesMax} places). Remove one first.',
              'Danh sách đã đầy (${AppConfig.savedPlacesMax} địa điểm). Hãy xóa bớt trước.')),
        ));
        return null;
      }
      return loc;
    case 'manage':
      await Routes.places(context);
      return null;
  }
  return null;
}

class PlacePreviewSheet extends StatefulWidget {
  const PlacePreviewSheet({super.key, required this.location});
  final Location location;

  @override
  State<PlacePreviewSheet> createState() => _PlacePreviewSheetState();
}

class _PlacePreviewSheetState extends State<PlacePreviewSheet> {
  HomeSnapshot? _snap;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = HomeSnapshot(await ApiClient.instance.home(widget.location.locationId));
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final f = Fmt.of(context);
    final settings = SettingsScope.of(context);
    final loc = widget.location;
    final saved = settings.isSaved(loc.locationId);
    final full = !saved && settings.placesFull;
    final cur = _snap?.current;
    final today = _snap?.today;

    Widget weather;
    if (_loading) {
      weather = Padding(padding: const EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: c.accent)));
    } else if (_error != null) {
      weather = Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: c.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(errorText(context, _error!), style: TextStyle(color: c.textSecondary))),
          TextButton(onPressed: _load, child: Text(tr(context, 'Retry', 'Thử lại'))),
        ],
      );
    } else {
      final cd = cur?.data;
      weather = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WeatherIcon(code: cd?.conditionCode ?? 'UNKNOWN', isDay: cd?.isDay, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueOrReason(
                      value: f.deg(cd?.temperatureC),
                      reason: cur == null ? null : reasonText(context, cur.status, cur.reasonCode),
                      style: TextStyle(fontSize: 48, fontWeight: FontWeight.w300, color: c.textPrimary, height: 1.05),
                    ),
                    Text(cd == null ? '-' : conditionLabel(context, cd.conditionCode, isDay: cd.isDay),
                        style: TextStyle(fontSize: 16, color: c.textSecondary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${tr(context, 'H', 'C')}: ${f.deg(today?.data?.maxC)}', style: TextStyle(color: c.textPrimary, fontSize: 16)),
                  Text('${tr(context, 'L', 'T')}: ${f.deg(today?.data?.minC)}', style: TextStyle(color: c.textSecondary, fontSize: 16)),
                ],
              ),
            ],
          ),
          if (cur != null && !cur.hasData) SectionNotice(status: cur.status, reason: cur.reasonCode, onRetry: _load, compact: true),
          if (cur != null) SourceFooter(source: cur.source, timezone: loc.timezone, stale: cur.isStale),
        ],
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(placeTitle(context, loc), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: c.textPrimary)),
          if (placeSubtitle(loc).isNotEmpty) Text(placeSubtitle(loc), style: TextStyle(color: c.textSecondary, fontSize: 15)),
          const SizedBox(height: 16),
          GlassCard(child: weather),
          const SizedBox(height: 16),
          if (full) ...[
            Text(
              tr(context,
                  'You can save up to ${AppConfig.savedPlacesMax} places. Remove a place in Manage places to add this one. Current location does not count toward the limit.',
                  'Bạn có thể lưu tối đa ${AppConfig.savedPlacesMax} địa điểm. Hãy xóa bớt trong Quản lý địa điểm để thêm nơi này. Vị trí hiện tại không tính vào giới hạn.'),
              style: TextStyle(color: c.textSecondary),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: tr(context, 'Manage places', 'Quản lý địa điểm'),
              icon: Icons.list_rounded,
              onPressed: () => Navigator.pop(context, 'manage'),
            ),
          ] else
            PrimaryButton(
              label: saved ? tr(context, 'Open', 'Mở') : tr(context, 'Add', 'Thêm'),
              icon: saved ? Icons.open_in_new_rounded : Icons.add_rounded,
              onPressed: () => Navigator.pop(context, saved ? 'open' : 'add'),
            ),
          if (saved)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr(context, 'Already in your places.', 'Đã có trong danh sách địa điểm.'),
                  textAlign: TextAlign.center, style: TextStyle(color: c.textMuted, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
