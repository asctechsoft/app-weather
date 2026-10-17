import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'place_preview.dart';

/// PLACE01 search. Debounced, min chars, stale responses discarded, never auto-selects.
/// Pops with the chosen [Location] (already saved) or null.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _Result {
  _Result(this.location, this.admin2);
  final Location location;
  final String? admin2;
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  int _seq = 0;
  String _query = '';
  bool _loading = false;
  Object? _error;
  List<_Result>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < AppConfig.searchMinChars) {
      _seq++; // invalidate any in-flight request
      setState(() {
        _query = q;
        _loading = false;
        _error = null;
        _results = null;
      });
      return;
    }
    _debounce = Timer(AppConfig.searchDebounce, () => _search(q));
  }

  Future<void> _search(String q) async {
    final id = ++_seq;
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });
    try {
      final lang = SettingsScope.read(context).effectiveLanguage;
      final res = await ApiClient.instance.searchLocations(q, lang);
      if (!mounted || id != _seq) return;
      final list = <_Result>[];
      for (final r in lm(res['results'])) {
        final lj = m(r['location']);
        if (lj == null || lj['locationId'] == null) continue;
        list.add(_Result(Location.fromJson(lj), s(r['admin2'])));
      }
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _seq) return;
      setState(() {
        _error = e;
        _loading = false;
        _results = null;
      });
    }
  }

  Future<void> _pick(Location loc) async {
    FocusScope.of(context).unfocus();
    final chosen = await showPlacePreview(context, loc);
    if (!mounted || chosen == null) return;
    Navigator.of(context).pop(chosen);
  }

  String _kindLabel(String kind) => switch (kind) {
        'city' => tr(context, 'City', 'Thành phố'),
        'administrative_area' => tr(context, 'Region', 'Vùng'),
        _ => tr(context, 'Place', 'Địa điểm'),
      };

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final settings = SettingsScope.of(context);

    // Names shared by several results get extra detail (admin2) so they are distinguishable.
    final nameCounts = <String, int>{};
    for (final r in _results ?? const <_Result>[]) {
      final k = (r.location.name ?? '').toLowerCase();
      nameCounts[k] = (nameCounts[k] ?? 0) + 1;
    }

    Widget body;
    if (_query.length < AppConfig.searchMinChars) {
      body = UnsupportedView(
        icon: Icons.travel_explore_rounded,
        title: tr(context, 'Find a city or region', 'Tìm thành phố hoặc vùng'),
        message: tr(context, 'Type at least ${AppConfig.searchMinChars} characters.', 'Nhập ít nhất ${AppConfig.searchMinChars} ký tự.'),
      );
    } else if (_loading && _results == null) {
      body = Center(child: CircularProgressIndicator(color: c.accent));
    } else if (_error != null) {
      final offline = _error is ApiException && (_error as ApiException).isNetwork;
      body = UnsupportedView(
        icon: offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
        title: offline ? tr(context, 'You are offline', 'Không có kết nối') : tr(context, 'Search failed', 'Tìm kiếm thất bại'),
        message: errorText(context, _error!),
        action: FilledButton(onPressed: () => _search(_query), child: Text(tr(context, 'Retry', 'Thử lại'))),
      );
    } else if (_results != null && _results!.isEmpty) {
      body = UnsupportedView(
        icon: Icons.search_off_rounded,
        title: tr(context, 'No places found', 'Không tìm thấy địa điểm'),
        message: tr(context, 'Nothing matches "$_query". Check the spelling or try a nearby larger city.',
            'Không có kết quả cho "$_query". Kiểm tra chính tả hoặc thử thành phố lớn gần đó.'),
      );
    } else {
      final results = _results ?? const <_Result>[];
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: results.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, k) {
          final r = results[k];
          final l = r.location;
          final dup = (nameCounts[(l.name ?? '').toLowerCase()] ?? 0) > 1;
          final region = [if (dup && r.admin2 != null && r.admin2 != l.admin1) r.admin2, l.admin1]
              .whereType<String>()
              .where((e) => e.isNotEmpty)
              .join(', ');
          final saved = settings.isSaved(l.locationId);
          return GlassCard(
            onTap: () => _pick(l),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.chipBg, borderRadius: BorderRadius.circular(10)),
                  child: Text(l.countryCode ?? '?', style: TextStyle(fontWeight: FontWeight.w700, color: c.textPrimary)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.name ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.textPrimary)),
                      if (region.isNotEmpty)
                        Text(region, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: 14)),
                      Text(l.country ?? l.countryCode ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.textPrimary.withValues(alpha: .85), fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: c.cardBorder)),
                      child: Text(_kindLabel(l.kind), style: TextStyle(fontSize: 12, color: c.textSecondary)),
                    ),
                    if (saved) ...[
                      const SizedBox(height: 4),
                      Icon(Icons.check_circle_rounded, size: 18, color: c.accent, semanticLabel: tr(context, 'Saved', 'Đã lưu')),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      );
    }

    return DetailScaffold(
      title: tr(context, 'Add place', 'Thêm địa điểm'),
      centerTitle: false,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text('${settings.savedPlaces.length}/${AppConfig.savedPlacesMax}', style: TextStyle(color: c.textSecondary)),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _ctl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (v) {
                final q = v.trim();
                if (q.length >= AppConfig.searchMinChars) {
                  _debounce?.cancel();
                  _search(q);
                }
              },
              style: TextStyle(color: c.textPrimary, fontSize: 17),
              decoration: InputDecoration(
                hintText: tr(context, 'Search city or region', 'Tìm thành phố hoặc vùng'),
                hintStyle: TextStyle(color: c.textMuted),
                prefixIcon: Icon(Icons.search_rounded, color: c.textSecondary),
                suffixIcon: _ctl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: tr(context, 'Clear', 'Xóa'),
                        icon: Icon(Icons.close_rounded, color: c.textSecondary),
                        onPressed: () {
                          _ctl.clear();
                          _onChanged('');
                        },
                      ),
                filled: true,
                fillColor: c.card,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide(color: c.cardBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide(color: c.accent)),
              ),
            ),
          ),
          if (_loading && _results != null) LinearProgressIndicator(minHeight: 2, color: c.accent, backgroundColor: Colors.transparent),
          Expanded(child: body),
        ],
      ),
    );
  }
}
