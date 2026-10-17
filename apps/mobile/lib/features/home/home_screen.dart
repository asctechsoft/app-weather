import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../ui/routes.dart';
import '../../ui/theme.dart';
import '../../ui/weather_icon.dart';
import '../../ui/widgets.dart';
import '../settings/rate_dialog.dart';
import 'app_drawer.dart';
import 'home_controller.dart';
import 'onboarding_screen.dart';
import 'sky_scene.dart';

/// HOME01. Current weather + insights are locked at the top; the rest follows CUSTOM01.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final HomeController ctrl;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scroll = ScrollController();
  bool _ratePromptChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ctrl = HomeController(SettingsScope.read(context));
    ctrl.addListener(_onCtrl);
    final def = ctrl.settings.defaultLocation;
    if (def != null) ctrl.select(def);
  }

  void _onCtrl() {
    if (mounted) setState(() {});
    if (!_ratePromptChecked && ctrl.snapshot != null && ctrl.error == null && !ctrl.loading) {
      _ratePromptChecked = true;
      maybeShowRatePrompt(context);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ctrl.removeListener(_onCtrl);
    ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final s = ctrl.settings;
    final last = ctrl.lastFetchAt;
    // Refresh on return only when the data is older than 10 minutes (no request storms).
    if (s.refresh.onReturn && (last == null || DateTime.now().difference(last) > const Duration(minutes: 10))) {
      ctrl.reload();
    }
  }

  Future<void> _addPlace() async {
    final loc = await Routes.search(context);
    if (loc != null && mounted) ctrl.select(loc);
  }

  void _openPlacePicker() {
    final s = SettingsScope.read(context);
    final c = SkyColors.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (s.gpsEnabled && s.gpsLocation != null)
              ListTile(
                leading: Icon(Icons.near_me_rounded, color: c.blue),
                title: Text(tr(context, 'Current location', 'Vị trí hiện tại')),
                selected: ctrl.active?.locationId == s.gpsLocation!.locationId,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  ctrl.select(s.gpsLocation!);
                },
              ),
            for (final p in s.savedPlaces)
              ListTile(
                leading: Icon(s.defaultMode == 'saved' && s.defaultLocationId == p.locationId ? Icons.star_rounded : Icons.place_outlined, color: c.textSecondary),
                title: Text(p.name ?? '-'),
                subtitle: Text([p.admin1, p.country].whereType<String>().join(', ')),
                selected: ctrl.active?.locationId == p.locationId,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  ctrl.select(p);
                },
              ),
            ListTile(
              leading: Icon(Icons.edit_location_alt_outlined, color: c.accent),
              title: Text(tr(context, 'Manage places', 'Quản lý địa điểm')),
              onTap: () {
                Navigator.pop(sheetCtx);
                Routes.places(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    // Saved place removed / default changed elsewhere → follow the new default.
    final active = ctrl.active;
    if (active != null && !active.isGps && !s.isSaved(active.locationId)) {
      final def = s.defaultLocation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (def != null) {
          ctrl.select(def);
        } else {
          setState(() => ctrl.active = null);
        }
      });
    }
    if (ctrl.active == null) {
      return OnboardingScreen(
        controller: ctrl,
        onReady: (loc) => ctrl.select(loc),
      );
    }

    final c = SkyColors.of(context);
    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(controller: ctrl),
      body: SkyBackground(
        child: RefreshIndicator(
          color: c.accent,
          onRefresh: () => ctrl.reload(manual: true),
          child: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final snap = ctrl.snapshot;
    final s = SettingsScope.of(context);
    final c = SkyColors.of(context);
    final loc = ctrl.active!;

    if (snap == null) {
      return ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _Header(location: loc, onMenu: () => _scaffoldKey.currentState?.openDrawer(), onAdd: _addPlace, onPick: _openPlacePicker),
          const SizedBox(height: 120),
          if (ctrl.loading) Center(child: CircularProgressIndicator(color: c.accent)),
          if (!ctrl.loading && ctrl.error != null)
            UnsupportedView(
              icon: Icons.cloud_off_rounded,
              title: tr(context, 'Could not load weather', 'Không tải được thời tiết'),
              message: errorText(context, ctrl.error!),
              action: FilledButton(onPressed: () => ctrl.reload(), child: Text(tr(context, 'Retry', 'Thử lại'))),
            ),
        ],
      );
    }

    final cur = snap.current.data;
    final sections = <Widget>[];
    for (final id in s.homeLayout.visible) {
      final w = switch (id) {
        'hourly' => _HourlyPreview(snap: snap),
        'daily' => _DailyPreview(snap: snap),
        'conditions' => _ConditionsGrid(snap: snap),
        'airQuality' => _AirQualityCard(snap: snap),
        'map' => _MapCard(snap: snap),
        'aurora' => _AuroraCard(snap: snap),
        'widgets' => _WidgetsCard(),
        _ => null,
      };
      if (w != null) sections.add(w);
    }

    return Stack(
      children: [
        if (s.appearance.weatherBackground)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 520,
            child: SkyScene(code: cur?.conditionCode ?? 'UNKNOWN', isDay: cur?.isDay, fadeTo: c.bgTop),
          ),
        ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            _Header(location: snap.location, onMenu: () => _scaffoldKey.currentState?.openDrawer(), onAdd: _addPlace, onPick: _openPlacePicker),
            if (ctrl.error != null || ctrl.fromCache)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: SectionNotice(
                  status: 'stale',
                  reason: ctrl.error != null ? 'UPSTREAM_REFRESH_FAILED' : null,
                  onRetry: ctrl.loading ? null : () => ctrl.reload(),
                  compact: true,
                ),
              ),
            _Hero(snap: snap, onDark: s.appearance.weatherBackground),
            _SunArc(snap: snap, onDark: s.appearance.weatherBackground),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Insights(snap: snap),
                  for (final w in sections) ...[const SizedBox(height: 14), w],
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.accent,
                      side: BorderSide(color: c.accent, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Routes.customizeHome(context),
                    icon: const Icon(Icons.tune_rounded),
                    label: Text(tr(context, 'Customize Home', 'Tùy chỉnh trang chủ'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 16),
                  _Footer(snap: snap, loading: ctrl.loading),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.location, required this.onMenu, required this.onAdd, required this.onPick});
  final Location location;
  final VoidCallback onMenu;
  final VoidCallback onAdd;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final onDark = SettingsScope.of(context).appearance.weatherBackground;
    final c = SkyColors.of(context);
    final fg = onDark ? Colors.white : c.textPrimary;
    final sub = onDark ? const Color(0xFFC9D3F5) : c.textSecondary;
    final name = location.isGps ? (location.name ?? tr(context, 'Current location', 'Vị trí hiện tại')) : (location.name ?? '-');
    Widget circle(IconData icon, VoidCallback onTap, String tip) => Tooltip(
          message: tip,
          child: InkResponse(
            onTap: onTap,
            radius: 28,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: fg.withValues(alpha: .6)), color: Colors.black.withValues(alpha: .12)),
              child: Icon(icon, color: fg),
            ),
          ),
        );
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            circle(Icons.menu_rounded, onMenu, tr(context, 'Menu', 'Menu')),
            Expanded(
              child: InkWell(
                onTap: onPick,
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 24, fontWeight: FontWeight.w600))),
                        Icon(Icons.keyboard_arrow_down_rounded, color: fg),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (location.isGps) Icon(Icons.near_me_outlined, size: 14, color: sub),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            [
                              if (location.country != null) location.country!,
                              if (location.isGps) tr(context, 'Current location', 'Vị trí hiện tại'),
                            ].join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: sub, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            circle(Icons.add_rounded, onAdd, tr(context, 'Add place', 'Thêm địa điểm')),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.snap, required this.onDark});
  final HomeSnapshot snap;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final cur = snap.current.data;
    final today = snap.today.data;
    final fg = onDark ? Colors.white : c.textPrimary;
    final sub = onDark ? const Color(0xFFD5DCF7) : c.textSecondary;
    final lilac = onDark ? const Color(0xFFC6CCFF) : c.textPrimary;
    final temp = cur?.temperatureC;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.dayShort(snap.localDate).toUpperCase(), style: TextStyle(color: sub, fontSize: 18, letterSpacing: 1)),
                Semantics(
                  label: '${tr(context, 'Temperature', 'Nhiệt độ')} ${f.degU(temp)}',
                  child: ShaderMask(
                    shaderCallback: (r) => SkyPalette.coralGradient.createShader(r),
                    child: Text(
                      temp == null ? Fmt.dash : '${f.temp(temp)!.round()}°',
                      style: const TextStyle(fontSize: 112, height: 1.05, fontWeight: FontWeight.w200, color: Colors.white),
                    ),
                  ),
                ),
                if (snap.current.status != 'ready')
                  SectionNotice(status: snap.current.status, reason: snap.current.reasonCode, compact: true),
                Text(cur == null ? Fmt.dash : conditionLabel(context, cur.conditionCode, isDay: cur.isDay),
                    style: TextStyle(color: lilac, fontSize: 32, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${tr(context, 'Feels like', 'Cảm giác như')} ${f.deg(cur?.feelsLikeC)}', style: TextStyle(color: fg, fontSize: 18)),
                const SizedBox(height: 6),
                Text('H ${f.deg(today?.maxC)}   |   L ${f.deg(today?.minC)}', style: TextStyle(color: fg, fontSize: 18)),
              ],
            ),
          ),
          // Compact wind & humidity on the background (no large card — removed in the new design).
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _MiniStat(icon: Icons.air_rounded, text: f.windU(cur?.windSpeedMs), color: fg, onTap: () => Routes.wind(context, snap.location)),
              const SizedBox(height: 8),
              _MiniStat(icon: Icons.water_drop_outlined, text: f.pct(cur?.humidityPct), color: fg, onTap: () => Routes.humidity(context, snap.location)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.text, required this.color, required this.onTap});
  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: .18), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: color), const SizedBox(width: 6), Text(text, style: TextStyle(color: color, fontSize: 14))]),
        ),
      );
}

/// Sunrise → sunset progress for the place's local day. Not an astronomical trajectory.
class _SunArc extends StatelessWidget {
  const _SunArc({required this.snap, required this.onDark});
  final HomeSnapshot snap;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final t = snap.today.data;
    final tz = snap.location.timezone;
    final rise = t?.sunriseAt;
    final set = t?.sunsetAt;
    final fg = onDark ? Colors.white : c.textPrimary;
    double? progress;
    if (rise != null && set != null) {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final a = DateTime.parse(rise).millisecondsSinceEpoch;
      final b = DateTime.parse(set).millisecondsSinceEpoch;
      progress = ((now - a) / (b - a)).clamp(0.0, 1.0);
    }
    return InkWell(
      onTap: () => Routes.sunMoon(context, snap.location),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Icon(Icons.wb_twilight_rounded, color: Color(0xFFFFB648)),
                const SizedBox(width: 6),
                Text(f.time(rise, tz), style: TextStyle(color: fg, fontSize: 16)),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: CustomPaint(painter: _ArcPainter(progress, c.blue)),
                  ),
                ),
                Text(f.time(set, tz), style: TextStyle(color: fg, fontSize: 16)),
                const SizedBox(width: 6),
                const Icon(Icons.wb_twilight_rounded, color: Color(0xFFFF8A5B)),
              ],
            ),
            Text(
              rise == null && set == null
                  ? tr(context, 'No sunrise or sunset today', 'Hôm nay không có mặt trời mọc/lặn')
                  : '${f.duration(t?.daylightSeconds)} ${tr(context, 'of daylight', 'ban ngày')}',
              style: TextStyle(color: onDark ? const Color(0xFFD5DCF7) : c.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.progress, this.rest);
  final double? progress;
  final Color rest;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(8, 6, size.width - 16, (size.height - 6) * 2);
    final bg = Paint()
      ..color = rest.withValues(alpha: .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, bg);
    final p = progress;
    if (p == null) return;
    final done = Paint()
      ..shader = SkyPalette.coralGradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi * p, false, done);
    final a = math.pi + math.pi * p;
    final pos = rect.center + Offset(math.cos(a) * rect.width / 2, math.sin(a) * rect.height / 2);
    canvas.drawCircle(pos, 9, Paint()..color = const Color(0x55FFC93C));
    canvas.drawCircle(pos, 6, Paint()..color = const Color(0xFFFFC93C));
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.progress != progress;
}

/// Weather insights carousel: app reminders (never presented as official alerts), max 3.
class _Insights extends StatefulWidget {
  const _Insights({required this.snap});
  final HomeSnapshot snap;

  @override
  State<_Insights> createState() => _InsightsState();
}

class _InsightsState extends State<_Insights> {
  int page = 0;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final f = Fmt.of(context);
    final sec = widget.snap.insights;
    final items = sec.data ?? const <Insight>[];
    final loc = widget.snap.location;

    if (items.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.lightbulb_outline_rounded, color: c.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow(tr(context, 'Weather insights', 'Gợi ý thời tiết')),
                  const SizedBox(height: 4),
                  Text(reasonText(context, sec.status, sec.reasonCode), style: TextStyle(color: c.textSecondary)),
                  Text(
                    tr(context, 'Official alerts: no verified source for this area yet.', 'Cảnh báo chính thức: chưa có nguồn xác minh cho khu vực này.'),
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    (String, String, String?, IconData, VoidCallback) describe(Insight it) {
      switch (it.type) {
        case 'uv':
          return (
            tr(context, 'High UV today', 'UV cao hôm nay'),
            it.fromLocal != null
                ? tr(context, 'Use sun protection ${f.wallHour(it.fromLocal)} – ${f.wallHour(it.toLocal)}', 'Nên chống nắng ${f.wallHour(it.fromLocal)} – ${f.wallHour(it.toLocal)}')
                : tr(context, 'Use sun protection', 'Nên chống nắng'),
            'UV ${f.uv(it.value)}',
            Icons.wb_sunny_outlined,
            () => Routes.uv(context, loc),
          );
        case 'rain':
          return (
            tr(context, 'Rain expected soon', 'Sắp có mưa'),
            tr(context, 'Around ${f.wallHour(it.fromLocal)} · ${f.precipU(it.value)} (forecast)', 'Khoảng ${f.wallHour(it.fromLocal)} · ${f.precipU(it.value)} (dự báo)'),
            null,
            Icons.umbrella_outlined,
            () => Routes.rain(context, loc),
          );
        default:
          return (
            tr(context, 'Unhealthy air', 'Không khí có hại'),
            aqiCategoryLabel(context, it.category),
            'AQI ${f.number(it.value)}',
            Icons.masks_outlined,
            () => Routes.airQuality(context, loc),
          );
      }
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [c.card, const Color(0x99F06A5A)]),
        border: Border.all(color: c.accent.withValues(alpha: .6)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 104,
            child: PageView.builder(
              itemCount: items.length,
              onPageChanged: (p) => setState(() => page = p),
              itemBuilder: (_, k) {
                final (title, body, badge, icon, onTap) = describe(items[k]);
                return InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.black.withValues(alpha: .18), border: Border.all(color: c.cardBorder)),
                          child: Icon(icon, color: c.accent, size: 30),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(tr(context, 'REMINDER FROM SKYWEATHER', 'NHẮC NHỞ TỪ SKYWEATHER'), style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: c.textSecondary)),
                              const SizedBox(height: 2),
                              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: c.textPrimary)),
                              Text(body, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary)),
                            ],
                          ),
                        ),
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(gradient: SkyPalette.coralGradient, borderRadius: BorderRadius.circular(20)),
                            child: Text(badge, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF3A1208))),
                          ),
                        Icon(Icons.chevron_right_rounded, color: c.textPrimary),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (items.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var k = 0; k < items.length; k++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: k == page ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(color: k == page ? c.accent : c.textSecondary, borderRadius: BorderRadius.circular(4)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HourlyPreview extends StatelessWidget {
  const _HourlyPreview({required this.snap});
  final HomeSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final sec = snap.hourly;
    final cur = snap.current.data;
    final hours = sec.data ?? const <HourlyRecord>[];
    // "Now" is the current observation-time model value; the next columns are the following hours.
    final nowMs = cur == null ? DateTime.now().millisecondsSinceEpoch : DateTime.parse(cur.validAt).millisecondsSinceEpoch;
    final next = hours.where((h) => DateTime.parse(h.time).millisecondsSinceEpoch > nowMs).take(4).toList();
    final nowRainPct = hours.isEmpty ? null : hours.first.rainProbabilityPct;
    final cols = <(String, String, bool?, double?, double?)>[
      (tr(context, 'Now', 'Bây giờ'), cur?.conditionCode ?? 'UNKNOWN', cur?.isDay, cur?.temperatureC, nowRainPct),
      for (final h in next) (f.wallHour(h.localTime), h.conditionCode, h.isDay, h.temperatureC, h.rainProbabilityPct),
    ];
    final temps = cols.map((e) => e.$4).toList();

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: () => Routes.hourly(context, snap.location, date: snap.localDate),
      child: Column(
        children: [
          CardHeader(title: tr(context, 'Hourly forecast', 'Dự báo theo giờ'), trailing: tr(context, '24 hours', '24 giờ'), onTap: () => Routes.hourly(context, snap.location, date: snap.localDate)),
          Divider(color: c.divider, height: 20),
          if (!sec.hasData)
            SectionNotice(status: sec.status, reason: sec.reasonCode)
          else ...[
            Row(
              children: [
                for (final col in cols)
                  Expanded(
                    child: Column(
                      children: [
                        Text(col.$1, style: TextStyle(color: c.textSecondary, fontSize: 14)),
                        const SizedBox(height: 6),
                        WeatherIcon(code: col.$2, isDay: col.$3, size: 40),
                        const SizedBox(height: 4),
                        Text(f.deg(col.$4), style: TextStyle(fontSize: 22, color: c.textPrimary)),
                      ],
                    ),
                  ),
              ],
            ),
            SizedBox(height: 46, child: CustomPaint(size: Size.infinite, painter: _MiniLine(temps, c.accent))),
            Row(
              children: [
                for (final col in cols)
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.water_drop_outlined, size: 16, color: c.blue),
                        const SizedBox(width: 4),
                        Text(f.pct(col.$5), style: TextStyle(color: c.textSecondary)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Polyline across equal columns; null values leave a gap (never joined as if complete).
class _MiniLine extends CustomPainter {
  _MiniLine(this.values, this.color);
  final List<double?> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final vals = values.whereType<double>().toList();
    if (vals.isEmpty) return;
    final lo = vals.reduce(math.min) - 1;
    final hi = vals.reduce(math.max) + 1;
    final colW = size.width / values.length;
    Offset? prev;
    final line = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (var k = 0; k < values.length; k++) {
      final v = values[k];
      if (v == null) {
        prev = null;
        continue;
      }
      final p = Offset(colW * (k + .5), size.height - 8 - (v - lo) / (hi - lo) * (size.height - 16));
      if (prev != null) canvas.drawLine(prev, p, line);
      canvas.drawCircle(p, 5, Paint()..color = color);
      prev = p;
    }
  }

  @override
  bool shouldRepaint(_MiniLine old) => old.values != values;
}

class _DailyPreview extends StatelessWidget {
  const _DailyPreview({required this.snap});
  final HomeSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final sec = snap.daily;
    final days = sec.data ?? const <DailyRecord>[];
    final first = days.take(3).toList();
    // Shared scale across the visible rows so bars are comparable.
    final lows = first.map((e) => e.minC).whereType<double>();
    final highs = first.map((e) => e.maxC).whereType<double>();
    final lo = lows.isEmpty ? 0.0 : lows.reduce(math.min);
    final hi = highs.isEmpty ? 1.0 : highs.reduce(math.max);
    final title = days.length >= 10
        ? tr(context, '10-day outlook', 'Dự báo 10 ngày')
        : tr(context, '${days.length}-day outlook', 'Dự báo ${days.length} ngày');

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        children: [
          CardHeader(title: title, trailing: tr(context, 'View forecast', 'Xem dự báo'), onTap: () => Routes.daily(context, snap.location)),
          Divider(color: c.divider, height: 20),
          if (!sec.hasData) SectionNotice(status: sec.status, reason: sec.reasonCode),
          for (final d in first)
            InkWell(
              onTap: () => Routes.hourly(context, snap.location, date: d.localDate),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.localDate == snap.localDate ? tr(context, 'Today', 'Hôm nay') : f.weekday(d.localDate), style: TextStyle(fontSize: 17, color: c.textPrimary)),
                          Text(f.monthDay(d.localDate).toUpperCase(), style: TextStyle(fontSize: 12, color: c.textSecondary)),
                        ],
                      ),
                    ),
                    WeatherIcon(code: d.conditionCode, isDay: true, size: 36),
                    const SizedBox(width: 10),
                    Expanded(child: Text(conditionLabel(context, d.conditionCode), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary))),
                    SizedBox(width: 40, child: Text(f.deg(d.minC), textAlign: TextAlign.right, style: TextStyle(color: c.textSecondary, fontSize: 16))),
                    SizedBox(width: 80, height: 8, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: RangeBar(lo: lo, hi: hi, min: d.minC, max: d.maxC))),
                    SizedBox(width: 36, child: Text(f.deg(d.maxC), style: TextStyle(color: c.textPrimary, fontSize: 16))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Temperature range bar on a shared scale [lo, hi].
class RangeBar extends StatelessWidget {
  const RangeBar({super.key, required this.lo, required this.hi, required this.min, required this.max, this.highlight = false});
  final double lo;
  final double hi;
  final double? min;
  final double? max;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final span = (hi - lo).abs() < 0.1 ? 1.0 : hi - lo;
      final a = min == null ? null : ((min! - lo) / span).clamp(0.0, 1.0) * w;
      final b = max == null ? null : ((max! - lo) / span).clamp(0.0, 1.0) * w;
      return Stack(
        alignment: Alignment.centerLeft,
        children: [
          Container(height: 6, decoration: BoxDecoration(color: c.chipBg, borderRadius: BorderRadius.circular(3))),
          if (a != null && b != null)
            Positioned(
              left: a,
              width: math.max(6, b - a),
              child: Container(height: 6, decoration: BoxDecoration(gradient: highlight ? null : SkyPalette.coralGradient, color: highlight ? Colors.white : null, borderRadius: BorderRadius.circular(3))),
            ),
        ],
      );
    });
  }
}

class _ConditionsGrid extends StatelessWidget {
  const _ConditionsGrid({required this.snap});
  final HomeSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final c = SkyColors.of(context);
    final cur = snap.current.data;
    final hl = snap.highlights.data;
    final loc = snap.location;
    final feels = m(hl?['feelsLike']);
    final pt = m(hl?['pressureTrend']);
    String feelsCaption() {
      final label = switch (s(feels?['label'])) {
        'warmer' => tr(context, 'warmer', 'nóng hơn'),
        'cooler' => tr(context, 'cooler', 'mát hơn'),
        'similar' => tr(context, 'similar', 'tương đương'),
        _ => null,
      };
      return '${tr(context, 'Actual', 'Thực tế')} ${f.deg(cur?.temperatureC)}${label == null ? '' : ' · $label'}';
    }

    final tiles = <Widget>[
      _MetricCard(icon: Icons.thermostat_rounded, label: tr(context, 'Feels like', 'Cảm giác như'), value: f.deg(cur?.feelsLikeC), caption: feelsCaption(), onTap: () => Routes.feelsLike(context, loc)),
      _MetricCard(
        icon: Icons.wb_sunny_outlined,
        iconColor: SkyPalette.uvColor(s(hl?['uvCategory'])),
        label: tr(context, 'UV index', 'Chỉ số UV'),
        value: f.uv(cur?.uvIndex),
        caption: uvCategoryLabel(context, s(hl?['uvCategory'])),
        level: cur?.uvIndex == null ? null : (cur!.uvIndex! / 11).clamp(0, 1).toDouble(),
        levelColor: SkyPalette.uvColor(s(hl?['uvCategory'])),
        onTap: () => Routes.uv(context, loc),
      ),
      _MetricCard(
        icon: Icons.air_rounded,
        label: tr(context, 'Wind', 'Gió'),
        value: f.windU(cur?.windSpeedMs),
        caption: [compassText(context, s(hl?['windCompass'])), if (cur?.windGustMs != null) '${tr(context, 'Gusts', 'Giật')} ${f.windU(cur!.windGustMs)}'].join(' · '),
        onTap: () => Routes.wind(context, loc),
      ),
      _MetricCard(
        icon: Icons.water_drop_outlined,
        label: tr(context, 'Humidity', 'Độ ẩm'),
        value: f.pct(cur?.humidityPct),
        caption: '${tr(context, 'Dew point', 'Điểm sương')} ${f.deg(cur?.dewPointC)}',
        level: cur?.humidityPct == null ? null : cur!.humidityPct! / 100,
        levelColor: c.blue,
        onTap: () => Routes.humidity(context, loc),
      ),
      _MetricCard(
        icon: Icons.grain_rounded,
        label: tr(context, 'Precipitation', 'Lượng mưa'),
        value: f.precipU(d(hl?['todayPrecipitationMm'])),
        caption: tr(context, 'Today, model estimate', 'Hôm nay, ước tính mô hình'),
        onTap: () => Routes.rain(context, loc),
      ),
      _MetricCard(
        icon: Icons.visibility_outlined,
        label: tr(context, 'Visibility', 'Tầm nhìn'),
        value: f.distanceU(cur?.visibilityM),
        caption: visibilityLabelText(context, s(hl?['visibilityCategory'])),
        level: cur?.visibilityM == null ? null : (cur!.visibilityM! / 20000).clamp(0, 1).toDouble(),
        levelColor: c.blue,
        onTap: () => Routes.visibility(context, loc),
      ),
      _MetricCard(
        icon: Icons.speed_rounded,
        label: tr(context, 'Pressure', 'Áp suất'),
        value: f.pressureU(cur?.seaLevelPressureHpa),
        caption: pressureTrendText(context, s(pt?['trend']), s(pt?['rate'])),
        onTap: () => Routes.pressure(context, loc),
      ),
      _MetricCard(
        icon: Icons.cloud_outlined,
        label: tr(context, 'Cloud cover', 'Mây che phủ'),
        value: f.pct(cur?.cloudCoverPct),
        caption: cur == null ? null : conditionLabel(context, cur.conditionCode, isDay: cur.isDay),
        level: cur?.cloudCoverPct == null ? null : cur!.cloudCoverPct! / 100,
        levelColor: c.blue,
        onTap: () => Routes.visibility(context, loc),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (snap.current.status != 'ready') SectionNotice(status: snap.current.status, reason: snap.current.reasonCode),
        LayoutBuilder(builder: (context, box) {
          final twoCols = box.maxWidth >= 330;
          final w = twoCols ? (box.maxWidth - 12) / 2 : box.maxWidth;
          return Wrap(spacing: 12, runSpacing: 12, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
        }),
        SourceFooter(source: snap.current.source, timezone: loc.timezone, stale: snap.current.isStale),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.label, required this.value, this.caption, this.onTap, this.level, this.levelColor, this.iconColor});
  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  final VoidCallback? onTap;
  final double? level;
  final Color? levelColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      child: SizedBox(
        height: 92,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: iconColor ?? c.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: 13)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ValueOrReason(value: value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.textPrimary)),
                  ),
                  if (caption != null) Text(caption!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(Icons.chevron_right_rounded, color: c.textMuted, size: 20),
                if (level != null) _LevelBars(level: level!, color: levelColor ?? c.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 5-bar level indicator derived from the actual value (not decorative).
class _LevelBars extends StatelessWidget {
  const _LevelBars({required this.level, required this.color});
  final double level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final filled = (level * 5).ceil().clamp(1, 5);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var k = 0; k < 5; k++)
          Container(
            margin: const EdgeInsets.only(left: 3),
            width: 5,
            height: 8.0 + k * 6,
            decoration: BoxDecoration(color: k < filled ? color : color.withValues(alpha: .2), borderRadius: BorderRadius.circular(3)),
          ),
      ],
    );
  }
}

class _AirQualityCard extends StatelessWidget {
  const _AirQualityCard({required this.snap});
  final HomeSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final f = Fmt.of(context);
    final sec = snap.airQuality;
    final aq = sec.data;
    final cat = s(aq?['category']);
    final value = d(aq?['usAqi']);
    return GlassCard(
      onTap: () => Routes.airQuality(context, snap.location),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: tr(context, 'Air quality', 'Chất lượng không khí'), trailing: 'US AQI', onTap: () => Routes.airQuality(context, snap.location)),
          const SizedBox(height: 10),
          if (!sec.hasData)
            SectionNotice(status: sec.status, reason: sec.reasonCode)
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(f.number(value), style: TextStyle(fontSize: 44, fontWeight: FontWeight.w700, color: SkyPalette.aqiColor(cat))),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(aqiCategoryLabel(context, cat), style: TextStyle(fontSize: 18, color: SkyPalette.aqiColor(cat), fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AqiScale(value: value),
            const SizedBox(height: 6),
            Text('PM2.5 ${f.number(d(aq?['pm25']))} μg/m³ · PM10 ${f.number(d(aq?['pm10']))} μg/m³', style: TextStyle(color: c.textSecondary, fontSize: 13)),
            Text(tr(context, 'Model data, not a monitoring station', 'Dữ liệu mô hình, không phải trạm quan trắc'), style: TextStyle(color: c.textMuted, fontSize: 12)),
          ],
          SourceFooter(source: sec.source, timezone: snap.location.timezone, stale: sec.isStale),
        ],
      ),
    );
  }
}

/// US AQI gradient scale 0–500 with a marker.
class AqiScale extends StatelessWidget {
  const AqiScale({super.key, required this.value});
  final double? value;

  // Piecewise position so each category gets equal width (as in the design).
  static double position(double v) {
    const stops = [0.0, 50, 100, 150, 200, 300, 500];
    for (var k = 1; k < stops.length; k++) {
      if (v <= stops[k]) return ((k - 1) + (v - stops[k - 1]) / (stops[k] - stops[k - 1])) / (stops.length - 1);
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: 18,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: 10,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), gradient: const LinearGradient(colors: SkyPalette.aqi)),
            ),
            if (value != null)
              Positioned(
                left: (position(value!) * w - 9).clamp(0, w - 18),
                child: Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: const Color(0xFFF2545B), width: 3))),
              ),
          ],
        ),
      );
    });
  }
}

class _MapCard extends StatelessWidget {
  const _MapCard({required this.snap});
  final HomeSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return GlassCard(
      onTap: () => Routes.map(context, snap.location),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: tr(context, 'Weather map', 'Bản đồ thời tiết'), onTap: () => Routes.map(context, snap.location)),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.map_outlined, color: c.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(reasonText(context, snap.map.status, snap.map.reasonCode), style: TextStyle(color: c.textSecondary))),
          ]),
        ],
      ),
    );
  }
}

class _AuroraCard extends StatelessWidget {
  const _AuroraCard({required this.snap});
  final HomeSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final f = Fmt.of(context);
    final sec = snap.aurora;
    final a = sec.data;
    final outlook = switch (s(a?['outlook'])) {
      'possible' => tr(context, 'Possible (experimental)', 'Có thể thấy (thử nghiệm)'),
      'possible_high_latitude' => tr(context, 'Only with strong activity', 'Chỉ khi hoạt động mạnh'),
      'unlikely' => tr(context, 'Unlikely here', 'Khó thấy ở đây'),
      _ => Fmt.dash,
    };
    return GlassCard(
      onTap: () => Routes.aurora(context, snap.location),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xFF0B1A33), Color(0xFF2EE59D), Color(0xFF0B1A33)]),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'Aurora forecast', 'Dự báo cực quang'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.textPrimary)),
                if (!sec.hasData)
                  SectionNotice(status: sec.status, reason: sec.reasonCode, compact: true)
                else
                  Text('Kp ${f.number(d(a?['kp']), digits: 1)} (${tr(context, 'global', 'toàn cầu')}) · $outlook', style: TextStyle(color: c.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.textMuted),
        ],
      ),
    );
  }
}

class _WidgetsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return GlassCard(
      onTap: () => Routes.widgets(context),
      child: Row(
        children: [
          Icon(Icons.grid_view_rounded, size: 36, color: c.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'Widgets', 'Widget'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.textPrimary)),
                Text(tr(context, 'Add weather to your home screen', 'Thêm thời tiết ra màn hình chính'), style: TextStyle(color: c.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.textMuted),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.snap, required this.loading});
  final HomeSnapshot snap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final f = Fmt.of(context);
    final fetched = snap.current.source?.fetchedAt;
    return Column(
      children: [
        Text(
          loading ? tr(context, 'Updating…', 'Đang cập nhật…') : '${tr(context, 'Updated', 'Cập nhật')} ${f.time(fetched, snap.location.timezone)}',
          style: TextStyle(color: c.textSecondary),
        ),
        TextButton(
          onPressed: () => Routes.dataSources(context, snap.location),
          child: Text('${tr(context, 'Weather data & attribution', 'Dữ liệu thời tiết & ghi nguồn')} ›', style: TextStyle(color: c.textSecondary)),
        ),
      ],
    );
  }
}
