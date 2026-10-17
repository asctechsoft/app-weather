import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// SOURCE01. Provider list comes from the server (never hard-coded); the last good
/// response is cached so attribution stays readable offline.
class DataSourcesScreen extends StatefulWidget {
  const DataSourcesScreen({super.key, this.location});
  final Location? location;

  @override
  State<DataSourcesScreen> createState() => _DataSourcesScreenState();
}

class _Loaded {
  _Loaded(this.json, {required this.fromCache, this.error});
  final Json json;
  final bool fromCache;
  final Object? error;
}

class _DataSourcesScreenState extends State<DataSourcesScreen> {
  static const _cacheKey = 'skyweather.datasources.v1';

  Future<_Loaded> _load() async {
    try {
      final json = await ApiClient.instance.dataSources(widget.location?.locationId);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, jsonEncode(json));
      } catch (_) {}
      return _Loaded(json, fromCache: false);
    } catch (e) {
      Json? cached;
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_cacheKey);
        if (raw != null) cached = (jsonDecode(raw) as Map).cast<String, dynamic>();
      } catch (_) {}
      if (cached == null) rethrow;
      return _Loaded(cached, fromCache: true, error: e);
    }
  }

  static String groupLabel(BuildContext context, String? g) => switch (g) {
        'weather' => tr(context, 'Current & forecast', 'Hiện tại & dự báo'),
        'air_quality' => tr(context, 'Air quality', 'Chất lượng không khí'),
        'places' => tr(context, 'Places & search', 'Địa điểm & tìm kiếm'),
        'astronomy' => tr(context, 'Sun & moon', 'Mặt trời & mặt trăng'),
        'aurora' => tr(context, 'Aurora', 'Cực quang'),
        'alerts' => tr(context, 'Official alerts', 'Cảnh báo chính thức'),
        'radar' => tr(context, 'Radar', 'Radar'),
        'map' => tr(context, 'Forecast map', 'Bản đồ dự báo'),
        final String other => other,
        _ => '-',
      };

  static IconData groupIcon(String? g) => switch (g) {
        'weather' => Icons.cloud_outlined,
        'air_quality' => Icons.eco_outlined,
        'places' => Icons.place_outlined,
        'astronomy' => Icons.wb_sunny_outlined,
        'aurora' => Icons.waves_rounded,
        'alerts' => Icons.warning_amber_rounded,
        'radar' => Icons.radar_rounded,
        'map' => Icons.map_outlined,
        _ => Icons.dataset_outlined,
      };

  static String kindLabel(BuildContext context, String? k) => switch (k) {
        'catalog' => tr(context, 'place catalog', 'danh mục địa danh'),
        'official' => tr(context, 'official', 'chính thức'),
        _ => dataKindLabel(context, k),
      };

  static String coverageLabel(BuildContext context, String? v) => switch (v) {
        'global' => tr(context, 'Global', 'Toàn cầu'),
        'global_index' => tr(context, 'Global index (Kp)', 'Chỉ số toàn cầu (Kp)'),
        'none' => tr(context, 'No coverage yet', 'Chưa có vùng phủ'),
        final String other => other,
        _ => '-',
      };

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'Could not open the link.', 'Không mở được liên kết.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return DetailScaffold(
      title: tr(context, 'Weather data & attribution', 'Dữ liệu thời tiết & ghi nguồn'),
      subtitle: widget.location?.name,
      body: AsyncLoader<_Loaded>(
        load: _load,
        builder: (context, data, reload) {
          final sources = lm(data.json['sources']);
          final active = sources.where((x) => x['status'] == 'active').toList();
          final mode = s(data.json['providerMode']);
          return PageList(
            children: [
              if (data.fromCache)
                GlassCard(
                  borderColor: c.accent.withValues(alpha: .6),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off_rounded, color: c.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr(context, 'Offline — showing the last saved list. Pull to refresh.', 'Đang ngoại tuyến — hiển thị danh sách đã lưu gần nhất. Kéo để làm mới.'),
                          style: TextStyle(color: c.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              if (mode != null && mode != 'live')
                Text(
                  tr(context, 'Server is in "$mode" mode: values are development data, not live weather.',
                      'Máy chủ đang ở chế độ "$mode": số liệu là dữ liệu phát triển, không phải thời tiết thực.'),
                  style: TextStyle(color: c.accent, fontSize: 13),
                ),
              Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 0), child: Eyebrow(tr(context, 'Sources', 'Nguồn dữ liệu'))),
              for (final src in sources) _sourceCard(context, src),
              Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 0), child: Eyebrow(tr(context, 'Attribution & licenses', 'Ghi nguồn & giấy phép'))),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (active.isEmpty) Text('-', style: TextStyle(color: c.textSecondary)),
                    for (final src in active)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(
                          '• ${s(src['attribution']) ?? s(src['name']) ?? '-'}${s(src['license']) != null ? ' — ${s(src['license'])}' : ''}',
                          style: TextStyle(color: c.textPrimary, height: 1.35),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      tr(context, 'Weather icons and backgrounds are drawn by the app. No map base layer is used in this build.',
                          'Biểu tượng và nền thời tiết do ứng dụng tự vẽ. Bản build này không dùng nền bản đồ.'),
                      style: TextStyle(color: c.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              InfoCard(
                icon: Icons.insights_rounded,
                title: tr(context, 'About forecast accuracy', 'Về độ chính xác dự báo'),
                body: tr(
                  context,
                  'Forecasts come from numerical weather models on a grid (often several kilometres wide), so each value represents an area around one point, not your exact street. Model data is updated on the provider\'s schedule and can lag behind sudden changes. It can differ from readings at a nearby weather station, which measure one spot. Each section shows its source, data type and time.',
                  'Dự báo lấy từ mô hình thời tiết số trên lưới (thường rộng vài km), nên mỗi giá trị đại diện cho một vùng quanh một điểm, không phải chính xác con phố của bạn. Dữ liệu mô hình cập nhật theo lịch của nhà cung cấp và có thể chậm so với thay đổi đột ngột. Số liệu có thể khác trạm quan trắc gần đó vì trạm chỉ đo tại một điểm. Mỗi mục đều ghi nguồn, loại dữ liệu và thời điểm.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sourceCard(BuildContext context, Json src) {
    final c = SkyColors.of(context);
    final group = s(src['group']);
    final status = s(src['status']);
    final isActive = status == 'active';
    final url = s(src['url']);
    final name = s(src['name']);

    Widget line(String k, String v) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 96, child: Text(k, style: TextStyle(color: c.textMuted, fontSize: 13))),
              Expanded(child: Text(v, style: TextStyle(color: c.textSecondary, fontSize: 13))),
            ],
          ),
        );

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(groupIcon(group), color: isActive ? c.blue : c.textMuted),
              const SizedBox(width: 10),
              Expanded(child: Text(groupLabel(context, group), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.textPrimary))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0x333CCB7F) : c.chipBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isActive ? tr(context, 'Active', 'Đang dùng') : (status == 'not_configured' ? tr(context, 'Not configured', 'Chưa cấu hình') : (status ?? '-')),
                  style: TextStyle(fontSize: 12, color: isActive ? const Color(0xFF3CCB7F) : c.textSecondary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(name ?? (isActive ? providerName(s(src['providerId'])) : tr(context, 'No provider configured yet', 'Chưa cấu hình nhà cung cấp')),
              style: TextStyle(color: c.textPrimary)),
          line(tr(context, 'Data type', 'Loại dữ liệu'), kindLabel(context, s(src['dataKind']))),
          line(tr(context, 'Coverage', 'Vùng phủ'), coverageLabel(context, s(src['coverage']))),
          if (s(src['license']) != null) line(tr(context, 'License', 'Giấy phép'), s(src['license'])!),
          if (url != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _open(url),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(Uri.tryParse(url)?.host ?? url, overflow: TextOverflow.ellipsis),
                style: TextButton.styleFrom(foregroundColor: c.blue, padding: EdgeInsets.zero),
              ),
            ),
        ],
      ),
    );
  }
}
