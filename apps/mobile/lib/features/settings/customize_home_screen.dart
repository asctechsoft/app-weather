import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'settings_screen.dart';

/// CUSTOM01. Current weather + insights are locked; the rest is a draft (order + hidden)
/// saved with "Save changes". Reset only changes the draft.
class CustomizeHomeScreen extends StatefulWidget {
  const CustomizeHomeScreen({super.key});

  @override
  State<CustomizeHomeScreen> createState() => _CustomizeHomeScreenState();
}

class _CustomizeHomeScreenState extends State<CustomizeHomeScreen> {
  late HomeLayout _saved;
  late List<String> _order;
  late Set<String> _hidden;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _saved = SettingsScope.read(context).homeLayout;
    _order = List.of(_saved.order);
    _hidden = Set.of(_saved.hidden);
  }

  bool get _dirty => !listEquals(_order, _saved.order) || !setEquals(_hidden, _saved.hidden);
  bool get _isDefault => listEquals(_order, HomeLayout.defaults.order) && setEquals(_hidden, HomeLayout.defaults.hidden);

  Future<void> _save() async {
    setState(() => _saving = true);
    await SettingsScope.read(context).setHomeLayout(HomeLayout(order: List.of(_order), hidden: Set.of(_hidden)));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _reset() => setState(() {
        _order = List.of(HomeLayout.defaults.order);
        _hidden = Set.of(HomeLayout.defaults.hidden);
      });

  static String label(BuildContext context, String id) => switch (id) {
        'hourly' => tr(context, 'Hourly forecast', 'Dự báo theo giờ'),
        'daily' => tr(context, '10-day outlook', 'Dự báo 10 ngày'),
        'conditions' => tr(context, 'Current conditions', 'Điều kiện hiện tại'),
        'airQuality' => tr(context, 'Air quality', 'Chất lượng không khí'),
        'map' => tr(context, 'Weather map', 'Bản đồ thời tiết'),
        'aurora' => tr(context, 'Aurora forecast', 'Dự báo cực quang'),
        'widgets' => tr(context, 'Widgets shortcut', 'Lối tắt Widget'),
        _ => id,
      };

  static IconData icon(String id) => switch (id) {
        'hourly' => Icons.schedule_rounded,
        'daily' => Icons.calendar_month_outlined,
        'conditions' => Icons.dashboard_outlined,
        'airQuality' => Icons.eco_outlined,
        'map' => Icons.map_outlined,
        'aurora' => Icons.waves_rounded,
        'widgets' => Icons.widgets_outlined,
        _ => Icons.view_agenda_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);

    Widget locked(IconData ic, String title) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(ic, color: c.textSecondary),
                const SizedBox(width: 14),
                Expanded(child: Text(title, style: TextStyle(fontSize: 17, color: c.textPrimary))),
                Tooltip(
                  message: tr(context, 'Always shown at the top', 'Luôn hiển thị ở đầu'),
                  child: Icon(Icons.lock_outline_rounded, color: c.textMuted),
                ),
              ],
            ),
          ),
        );

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
          child: Text(
            tr(context, 'Drag to reorder and choose which cards appear on Home.', 'Kéo để sắp xếp và chọn thẻ hiển thị trên trang chủ.'),
            style: TextStyle(color: c.textSecondary, fontSize: 15),
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Eyebrow(tr(context, 'Locked', 'Cố định'))),
        locked(Icons.thermostat_rounded, tr(context, 'Current weather', 'Thời tiết hiện tại')),
        locked(Icons.lightbulb_outline_rounded, tr(context, 'Weather insights', 'Nhắc nhở thời tiết')),
        Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 8), child: Eyebrow(tr(context, 'Sections', 'Các mục'))),
      ],
    );

    final footer = Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: c.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(context, 'Hiding a card does not turn off its notifications. Sun & moon is in the menu.',
                  'Ẩn một thẻ không tắt thông báo tương ứng. Mặt trời & mặt trăng nằm trong menu.'),
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );

    return DraftGuard(
      dirty: _dirty && !_saving,
      child: DetailScaffold(
        title: tr(context, 'Customize Home', 'Tùy chỉnh trang chủ'),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: _isDefault ? null : _reset,
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(tr(context, 'Reset', 'Đặt lại')),
            style: TextButton.styleFrom(foregroundColor: c.textPrimary),
          ),
        ],
        body: Column(
          children: [
            Expanded(
              child: ReorderableListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                buildDefaultDragHandles: false,
                header: header,
                footer: footer,
                onReorder: (oldIndex, newIndex) => setState(() {
                  final item = _order.removeAt(oldIndex);
                  _order.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
                }),
                children: [
                  for (var k = 0; k < _order.length; k++)
                    Padding(
                      key: ValueKey(_order[k]),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                        child: Row(
                          children: [
                            ReorderableDragStartListener(
                              index: k,
                              child: Semantics(
                                label: tr(context, 'Drag to reorder', 'Kéo để sắp xếp'),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Icon(Icons.drag_indicator_rounded, color: c.textMuted),
                                ),
                              ),
                            ),
                            Icon(icon(_order[k]), color: _hidden.contains(_order[k]) ? c.textMuted : c.textSecondary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                label(context, _order[k]),
                                style: TextStyle(fontSize: 17, color: _hidden.contains(_order[k]) ? c.textMuted : c.textPrimary),
                              ),
                            ),
                            Switch(
                              value: !_hidden.contains(_order[k]),
                              onChanged: (v) => setState(() {
                                final id = _order[k];
                                v ? _hidden.remove(id) : _hidden.add(id);
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: PrimaryButton(label: tr(context, 'Save changes', 'Lưu thay đổi'), busy: _saving, onPressed: _dirty ? _save : null),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
