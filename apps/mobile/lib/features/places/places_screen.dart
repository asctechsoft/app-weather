import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

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

/// PLACE01. One batch /summaries call for the whole list, per-row error state,
/// star = the single default (shared with DEFAULT01), edit mode for reorder + delete.
/// The GPS entry is separate and does not use one of the 20 slots.
class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  final _gen = RequestGeneration();
  Map<String, Json> _items = {};
  Set<String> _requested = {};
  bool _loading = false;
  Object? _error;
  bool _edit = false;
  bool _locating = false;

  AppSettings get _settings => SettingsScope.read(context);

  List<String> _ids(AppSettings s) => [
        if (s.gpsEnabled && s.gpsLocation != null) s.gpsLocation!.locationId,
        ...s.savedPlaces.map((p) => p.locationId),
      ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ids = _ids(SettingsScope.of(context));
    // Reload only when a place appears that was not part of the last batch (reorder/delete don't refetch).
    if (ids.any((id) => !_requested.contains(id))) _load(ids, notify: false);
  }

  Future<void> _load(List<String> ids, {bool notify = true}) async {
    final g = _gen.next();
    _requested = ids.toSet();
    if (ids.isEmpty) {
      _items = {};
      _loading = false;
      if (notify) setState(() {});
      return;
    }
    _loading = true;
    _error = null;
    if (notify) setState(() {});
    try {
      final res = await ApiClient.instance.summaries(ids);
      if (!mounted || !_gen.isCurrent(g)) return;
      final map = <String, Json>{};
      for (final it in lm(res['items'])) {
        final id = s(it['locationId']);
        if (id != null) map[id] = it;
      }
      setState(() {
        _items = map;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || !_gen.isCurrent(g)) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _reload() => _load(_ids(_settings));

  // ---- GPS ----
  Future<void> _toggleGps(bool on) async {
    final st = _settings;
    if (!on) {
      final wasDefault = st.defaultMode == 'gps';
      await st.setGps(enabled: false);
      if (!mounted) return;
      if (wasDefault) {
        _snack(st.defaultLocation == null
            ? tr(context, 'Current location is off. Choose or add a default place.', 'Đã tắt vị trí hiện tại. Hãy chọn hoặc thêm địa điểm mặc định.')
            : tr(context, 'Default changed to ${placeTitle(context, st.defaultLocation!)}.', 'Đã đổi mặc định sang ${placeTitle(context, st.defaultLocation!)}.'));
      }
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.near_me_outlined),
        title: Text(tr(context, 'Use your current location?', 'Dùng vị trí hiện tại?')),
        content: Text(tr(
          context,
          'SkyWeather uses your position only while the app is open, to show weather for where you are. Your saved places are kept. You can turn this off at any time.',
          'SkyWeather chỉ dùng vị trí khi ứng dụng đang mở để hiển thị thời tiết nơi bạn đang ở. Các địa điểm đã lưu vẫn được giữ. Bạn có thể tắt bất cứ lúc nào.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'Not now', 'Để sau'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'Continue', 'Tiếp tục'))),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _locating = true);
    await _locate();
    if (mounted) setState(() => _locating = false);
  }

  Future<void> _locate() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!serviceOn) {
        _snack(tr(context, 'Location services are off on this device.', 'Dịch vụ vị trí trên thiết bị đang tắt.'),
            actionLabel: tr(context, 'Settings', 'Cài đặt'), action: Geolocator.openLocationSettings);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (!mounted) return;
      if (perm == LocationPermission.deniedForever) {
        _snack(tr(context, 'Location permission is blocked. Allow it in app settings, or search for a place.', 'Quyền vị trí đang bị chặn. Hãy cho phép trong cài đặt ứng dụng hoặc tìm địa điểm.'),
            actionLabel: tr(context, 'Settings', 'Cài đặt'), action: Geolocator.openAppSettings);
        return;
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.unableToDetermine) {
        _snack(tr(context, 'Location permission was not granted. You can still search for places.', 'Chưa được cấp quyền vị trí. Bạn vẫn có thể tìm địa điểm.'));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
      );
      Location loc;
      try {
        loc = Location.fromJson(await ApiClient.instance.resolveGps(pos.latitude, pos.longitude, pos.accuracy));
      } catch (e) {
        if (mounted) _snack(errorText(context, e));
        return;
      }
      if (!mounted) return;
      await _settings.setGps(enabled: true, location: loc);
    } catch (_) {
      if (mounted) _snack(tr(context, 'Could not get your position. Try again outdoors or later.', 'Không lấy được vị trí. Hãy thử lại ở nơi thoáng hoặc sau.'));
    }
  }

  void _snack(String text, {String? actionLabel, Future<bool> Function()? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      action: action == null ? null : SnackBarAction(label: actionLabel ?? 'OK', onPressed: () => action()),
    ));
  }

  // ---- saved places ----
  Future<void> _addPlace() async {
    if (_settings.placesFull) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(context, 'Your list is full', 'Danh sách đã đầy')),
          content: Text(tr(context,
              'You can save up to ${AppConfig.savedPlacesMax} places. Remove one to add another. Current location does not count.',
              'Bạn có thể lưu tối đa ${AppConfig.savedPlacesMax} địa điểm. Hãy xóa bớt để thêm nơi khác. Vị trí hiện tại không tính.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'Close', 'Đóng'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _edit = true);
              },
              child: Text(tr(context, 'Edit list', 'Sửa danh sách')),
            ),
          ],
        ),
      );
      return;
    }
    await Routes.search(context);
  }

  Future<void> _delete(Location p) async {
    final st = _settings;
    final name = placeTitle(context, p);
    final isDefault = st.defaultMode == 'saved' && st.defaultLocationId == p.locationId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'Remove $name?', 'Xóa $name?')),
        content: Text(isDefault
            ? tr(context, 'This is your default place. You will choose a new default next.', 'Đây là địa điểm mặc định. Bạn sẽ chọn mặc định mới ở bước tiếp theo.')
            : tr(context, 'It will be removed from your places on this device.', 'Địa điểm sẽ bị xóa khỏi danh sách trên thiết bị này.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'Cancel', 'Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'Remove', 'Xóa'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    if (isDefault) {
      final others = st.savedPlaces.where((x) => x.locationId != p.locationId).toList();
      final hasGps = st.gpsEnabled;
      if (others.isNotEmpty || hasGps) {
        // (mode, locationId)
        final pick = await showDialog<(String, String?)>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(tr(context, 'Choose a new default', 'Chọn mặc định mới')),
            children: [
              if (hasGps)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, ('gps', null)),
                  child: Row(children: [const Icon(Icons.near_me_outlined, size: 20), const SizedBox(width: 10), Text(tr(context, 'Current location', 'Vị trí hiện tại'))]),
                ),
              for (final o in others)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, ('saved', o.locationId)),
                  child: Row(children: [
                    const Icon(Icons.place_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(placeTitle(context, o), overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ],
          ),
        );
        if (!mounted) return;
        await st.removePlace(p.locationId);
        if (pick != null) {
          await st.setDefault(mode: pick.$1, locationId: pick.$2);
        }
        if (!mounted) return;
        // If the user dismissed the picker, settings auto-repair chose one: say which.
        _snack(tr(context, 'Removed $name. Default: ${defaultLocationText(context, st)}.', 'Đã xóa $name. Mặc định: ${defaultLocationText(context, st)}.'));
        return;
      }
    }
    await st.removePlace(p.locationId);
    if (!mounted) return;
    _snack(st.savedPlaces.isEmpty && !st.gpsEnabled
        ? tr(context, 'Removed $name. Add a place or use your current location to continue.', 'Đã xóa $name. Hãy thêm địa điểm hoặc dùng vị trí hiện tại để tiếp tục.')
        : tr(context, 'Removed $name.', 'Đã xóa $name.'));
  }

  // ---- UI ----
  Widget _weather(BuildContext context, String id, Location loc) {
    final c = SkyColors.of(context);
    final f = Fmt.of(context);
    final it = _items[id];
    if (it == null || (it['status'] != 'ready' && it['status'] != 'stale')) {
      if (_loading) return SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent));
      final reason = it == null ? null : s(it['reasonCode']);
      return Tooltip(
        message: _error != null ? errorText(context, _error!) : reasonText(context, s(it?['status']) ?? 'error', reason),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: c.textMuted, size: 20),
            const SizedBox(width: 6),
            Text(Fmt.dash, style: TextStyle(fontSize: 24, color: c.textSecondary)),
          ],
        ),
      );
    }
    final code = s(it['conditionCode']) ?? 'UNKNOWN';
    final isDay = it['isDay'] as bool?;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WeatherIcon(code: code, isDay: isDay, size: 36),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(f.deg(d(it['temperatureC'])), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w400, color: c.textPrimary, height: 1.1)),
            Text('${tr(context, 'H', 'C')}:${f.deg(d(it['maxC']))} ${tr(context, 'L', 'T')}:${f.deg(d(it['minC']))}',
                style: TextStyle(fontSize: 12, color: c.textSecondary)),
          ],
        ),
      ],
    );
  }

  Widget _placeInfo(BuildContext context, String id, Location loc) {
    final c = SkyColors.of(context);
    final f = Fmt.of(context);
    final it = _items[id];
    final localTime = s(it?['localTime']);
    final code = s(it?['conditionCode']);
    final sub = placeSubtitle(loc);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(placeTitle(context, loc), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.textPrimary)),
        if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.textSecondary)),
        Text(
          [
            if (localTime != null) '${tr(context, 'Local', 'Giờ địa phương')} ${f.wallTime(localTime)}',
            if (code != null && (it?['status'] == 'ready' || it?['status'] == 'stale')) conditionLabel(context, code, isDay: it?['isDay'] as bool?),
            if (it?['status'] == 'stale') tr(context, 'may be out of date', 'có thể đã cũ'),
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: c.textMuted),
        ),
      ],
    );
  }

  Widget _star(AppSettings st, {required bool isDefault, required VoidCallback onSet}) {
    final c = SkyColors.of(context);
    return IconButton(
      tooltip: isDefault ? tr(context, 'Default place', 'Địa điểm mặc định') : tr(context, 'Set as default', 'Đặt làm mặc định'),
      onPressed: isDefault ? null : onSet,
      icon: Icon(isDefault ? Icons.star_rounded : Icons.star_outline_rounded, color: isDefault ? c.accent : c.textSecondary),
    );
  }

  Widget _gpsCard(BuildContext context, AppSettings st) {
    final c = SkyColors.of(context);
    final gps = st.gpsLocation;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.near_me_outlined, color: st.gpsEnabled ? c.blue : c.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, 'Use current location', 'Dùng vị trí hiện tại'), style: TextStyle(fontSize: 17, color: c.textPrimary)),
                    Text(
                      tr(context, 'Separate from your saved places', 'Tách riêng, không tính vào danh sách đã lưu'),
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              if (_locating)
                Padding(padding: const EdgeInsets.all(12), child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: c.accent)))
              else
                Switch(value: st.gpsEnabled, onChanged: _toggleGps),
            ],
          ),
          if (st.gpsEnabled && gps != null) ...[
            Divider(color: c.divider, height: 16),
            Row(
              children: [
                const SizedBox(width: 4),
                Expanded(child: _placeInfo(context, gps.locationId, gps)),
                _weather(context, gps.locationId, gps),
                _star(st, isDefault: st.defaultMode == 'gps', onSet: () => st.setDefault(mode: 'gps')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final st = SettingsScope.of(context);
    final places = st.savedPlaces;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _gpsCard(context, st),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              Expanded(child: Eyebrow(tr(context, 'Saved places', 'Địa điểm đã lưu'))),
              Text('${places.length}/${AppConfig.savedPlacesMax}', style: TextStyle(color: st.placesFull ? c.accent : c.textSecondary)),
            ],
          ),
        ),
        if (_error != null && !_loading)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SectionNotice(status: 'error', reason: null, onRetry: _reload, compact: true),
          ),
        if (places.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(tr(context, 'No saved places yet.', 'Chưa có địa điểm nào.'), textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary)),
          ),
      ],
    );

    final footer = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryButton(label: tr(context, 'Add place', 'Thêm địa điểm'), icon: Icons.add_rounded, onPressed: _addPlace),
          if (_edit && places.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(tr(context, 'Drag ≡ to reorder. Order is used on Home.', 'Kéo ≡ để sắp xếp. Thứ tự này dùng ở trang chủ.'),
                  textAlign: TextAlign.center, style: TextStyle(color: c.textMuted, fontSize: 13)),
            ),
        ],
      ),
    );

    return DetailScaffold(
      title: tr(context, 'Manage places', 'Quản lý địa điểm'),
      centerTitle: false,
      actions: [
        if (places.isNotEmpty)
          TextButton(
            onPressed: () => setState(() => _edit = !_edit),
            child: Text(_edit ? tr(context, 'Done', 'Xong') : tr(context, 'Edit', 'Sửa'), style: TextStyle(color: c.accent, fontSize: 16)),
          )
        else
          const SizedBox(width: 48),
      ],
      body: RefreshIndicator(
        color: c.accent,
        onRefresh: _reload,
        child: ReorderableListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          buildDefaultDragHandles: false,
          header: header,
          footer: footer,
          onReorder: (oldIndex, newIndex) => st.reorderPlaces(oldIndex, newIndex),
          children: [
            for (var k = 0; k < places.length; k++)
              Padding(
                key: ValueKey(places[k].locationId),
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  padding: EdgeInsets.fromLTRB(_edit ? 0 : 14, 8, 4, 8),
                  child: Row(
                    children: [
                      if (_edit)
                        ReorderableDragStartListener(
                          index: k,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            child: Icon(Icons.drag_handle_rounded, color: c.textMuted, semanticLabel: tr(context, 'Drag to reorder', 'Kéo để sắp xếp')),
                          ),
                        ),
                      Expanded(child: _placeInfo(context, places[k].locationId, places[k])),
                      const SizedBox(width: 8),
                      if (!_edit) _weather(context, places[k].locationId, places[k]),
                      _star(
                        st,
                        isDefault: st.defaultMode == 'saved' && st.defaultLocationId == places[k].locationId,
                        onSet: () => st.setDefault(mode: 'saved', locationId: places[k].locationId),
                      ),
                      if (_edit)
                        IconButton(
                          tooltip: tr(context, 'Remove', 'Xóa'),
                          onPressed: () => _delete(places[k]),
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
