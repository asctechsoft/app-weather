import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../ui/theme.dart';
import '../../ui/weather_icon.dart';
import '../../ui/widgets.dart';

/// WIDGET01. Previews use the default place's current data and the user's units.
/// The OS widget itself needs a native extension that is not part of this build — said plainly.
class WidgetsScreen extends StatefulWidget {
  const WidgetsScreen({super.key});

  @override
  State<WidgetsScreen> createState() => _WidgetsScreenState();
}

class _WidgetsScreenState extends State<WidgetsScreen> {
  String _size = 'small';
  final _gen = RequestGeneration();
  HomeSnapshot? _snap;
  bool _loading = false;
  Object? _error;
  String? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = SettingsScope.of(context).defaultLocation;
    if (loc != null && loc.locationId != _loadedFor) _load(loc);
  }

  Future<void> _load(Location loc) async {
    final g = _gen.next();
    _loadedFor = loc.locationId;
    // No setState here: also called from didChangeDependencies (a build follows anyway).
    _loading = true;
    _error = null;
    try {
      final snap = HomeSnapshot(await ApiClient.instance.home(loc.locationId));
      if (!mounted || !_gen.isCurrent(g)) return;
      setState(() {
        _snap = snap;
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

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final s = SettingsScope.of(context);
    final loc = s.defaultLocation;

    Widget status;
    if (loc == null) {
      status = Text(tr(context, 'Choose a default place to see a preview with real data.', 'Chọn vị trí mặc định để xem trước bằng dữ liệu thực.'),
          style: TextStyle(color: c.textSecondary));
    } else if (_loading && _snap == null) {
      status = Row(children: [
        SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
        const SizedBox(width: 10),
        Text(tr(context, 'Loading preview…', 'Đang tải bản xem trước…'), style: TextStyle(color: c.textSecondary)),
      ]);
    } else if (_error != null && _snap == null) {
      status = Row(children: [
        Expanded(child: Text(errorText(context, _error!), style: TextStyle(color: c.textSecondary))),
        TextButton(onPressed: () {
          _load(loc);
          setState(() {});
        }, child: Text(tr(context, 'Retry', 'Thử lại'))),
      ]);
    } else {
      status = const SizedBox.shrink();
    }

    return DetailScaffold(
      title: tr(context, 'Widgets', 'Widget'),
      centerTitle: false,
      body: PageList(
        children: [
          PillTabs<String>(
            items: [
              ('small', tr(context, 'Small', 'Nhỏ'), null),
              ('medium', tr(context, 'Medium', 'Vừa'), null),
              ('large', tr(context, 'Large', 'Lớn'), null),
            ],
            selected: _size,
            onChanged: (v) => setState(() => _size = v),
          ),
          Center(
            child: Text(
              switch (_size) {
                'small' => tr(context, 'Current weather · Android 2×2', 'Thời tiết hiện tại · Android 2×2'),
                'medium' => tr(context, 'Hourly · Android 4×2', 'Theo giờ · Android 4×2'),
                _ => tr(context, 'Hourly + days · Android 4×4', 'Theo giờ + ngày · Android 4×4'),
              },
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
          ),
          Center(child: _WidgetMock(size: _size, snap: _snap, place: loc)),
          status,
          InfoCard(
            icon: Icons.construction_rounded,
            title: tr(context, 'Not available in this build yet', 'Bản build này chưa có widget'),
            body: tr(
              context,
              'Home-screen widgets need a native Android (App Widget) or iOS (WidgetKit) extension, which is not included in this build yet. The preview above shows how it is planned to look with your units.',
              'Widget màn hình chính cần phần mở rộng gốc trên Android (App Widget) hoặc iOS (WidgetKit), bản build này chưa có. Bản xem trước ở trên cho thấy thiết kế dự kiến theo đơn vị của bạn.',
            ),
          ),
          InfoCard(
            icon: Icons.touch_app_outlined,
            title: tr(context, 'How widgets are added', 'Cách thêm widget'),
            body: tr(
              context,
              'Once available, widgets are added from your launcher, not from inside the app: on Android, long-press an empty area of the Home screen → Widgets → SkyWeather; on iPhone, long-press the Home screen → + → SkyWeather. Sizes vary by launcher.',
              'Khi có, widget được thêm từ màn hình chính, không phải từ trong ứng dụng: trên Android, nhấn giữ vùng trống → Widget → SkyWeather; trên iPhone, nhấn giữ màn hình chính → + → SkyWeather. Kích thước tùy launcher.',
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetMock extends StatelessWidget {
  const _WidgetMock({required this.size, required this.snap, required this.place});
  final String size;
  final HomeSnapshot? snap;
  final Location? place;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final cur = snap?.current.data;
    final today = snap?.today.data;
    final name = place?.name ?? snap?.location.name ?? (place?.isGps == true ? tr(context, 'Current location', 'Vị trí hiện tại') : '-');
    const fg = Colors.white;
    const fg2 = Color(0xCCFFFFFF);

    final width = switch (size) { 'small' => 170.0, _ => 340.0 };
    final height = switch (size) { 'small' => 170.0, 'medium' => 170.0, _ => 340.0 };

    final head = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w600)),
              Text(f.deg(cur?.temperatureC), style: const TextStyle(color: fg, fontSize: 40, fontWeight: FontWeight.w300, height: 1.1)),
            ],
          ),
        ),
        WeatherIcon(code: cur?.conditionCode ?? 'UNKNOWN', isDay: cur?.isDay, size: 44),
      ],
    );
    final cond = Text(
      cur == null ? '-' : conditionLabel(context, cur.conditionCode, isDay: cur.isDay),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: fg2, fontSize: 13),
    );
    final hl = Text('H:${f.deg(today?.maxC)}  L:${f.deg(today?.minC)}', style: const TextStyle(color: fg2, fontSize: 13));

    List<HourlyRecord> nextHours() {
      final all = snap?.hourly.data ?? const <HourlyRecord>[];
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 59));
      return all.where((h) => (DateTime.tryParse(h.time)?.isAfter(now) ?? false)).take(5).toList();
    }

    Widget hours() {
      final list = nextHours();
      if (list.isEmpty) return const Text('-', style: TextStyle(color: fg2));
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final h in list)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(f.wallHour(h.localTime), style: const TextStyle(color: fg2, fontSize: 11)),
                const SizedBox(height: 2),
                WeatherIcon(code: h.conditionCode, isDay: h.isDay, size: 24),
                Text(f.deg(h.temperatureC), style: const TextStyle(color: fg, fontSize: 13)),
              ],
            ),
        ],
      );
    }

    Widget days() {
      final list = (snap?.daily.data ?? const <DailyRecord>[]).take(4).toList();
      if (list.isEmpty) return const Text('-', style: TextStyle(color: fg2));
      return Column(
        children: [
          for (final d in list)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(width: 48, child: Text(f.weekday(d.localDate), style: const TextStyle(color: fg, fontSize: 13))),
                  WeatherIcon(code: d.conditionCode, size: 22),
                  const Spacer(),
                  Text('${f.deg(d.minC)} / ${f.deg(d.maxC)}', style: const TextStyle(color: fg, fontSize: 13)),
                ],
              ),
            ),
        ],
      );
    }

    final body = switch (size) {
      'small' => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head, const Spacer(), cond, hl]),
      'medium' => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head, Row(children: [Expanded(child: cond), hl]), const Spacer(), hours()]),
      _ => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            head,
            Row(children: [Expanded(child: cond), hl]),
            const SizedBox(height: 12),
            hours(),
            const Divider(color: Color(0x33FFFFFF), height: 20),
            days(),
          ],
        ),
    };

    return LayoutBuilder(
      builder: (context, box) {
        final scale = box.maxWidth < width ? box.maxWidth / width : 1.0;
        return SizedBox(
          width: width * scale,
          height: height * scale,
          child: FittedBox(
            child: Container(
              width: width,
              height: height,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B6FD8), Color(0xFF14295A)]),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 8))],
              ),
              child: body,
            ),
          ),
        );
      },
    );
  }
}
