import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'settings_screen.dart';

/// REFRESH01. Client refresh policy only; the server's provider TTL is unchanged.
class RefreshScreen extends StatefulWidget {
  const RefreshScreen({super.key});

  @override
  State<RefreshScreen> createState() => _RefreshScreenState();
}

class _RefreshScreenState extends State<RefreshScreen> {
  late RefreshPrefs _saved;
  late RefreshPrefs _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _saved = SettingsScope.read(context).refresh;
    _draft = _saved;
  }

  bool get _dirty =>
      _draft.onOpen != _saved.onOpen ||
      _draft.onReturn != _saved.onReturn ||
      _draft.background != _saved.background ||
      _draft.intervalMinutes != _saved.intervalMinutes ||
      _draft.wifiOnly != _saved.wifiOnly;

  Future<void> _save() async {
    setState(() => _saving = true);
    await SettingsScope.read(context).setRefresh(_draft);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return DraftGuard(
      dirty: _dirty && !_saving,
      child: DetailScaffold(
        title: tr(context, 'Refresh preferences', 'Tùy chọn làm mới'),
        centerTitle: false,
        body: BodyWithAction(
          action: PrimaryButton(label: tr(context, 'Save', 'Lưu'), busy: _saving, onPressed: _dirty ? _save : null),
          children: [
            SettingsGroup(
              title: tr(context, 'Automatic refresh', 'Làm mới tự động'),
              children: [
                SettingsSwitchRow(
                  icon: Icons.open_in_new_rounded,
                  title: tr(context, 'Refresh when app opens', 'Làm mới khi mở ứng dụng'),
                  value: _draft.onOpen,
                  onChanged: (v) => setState(() => _draft = _draft.copyWith(onOpen: v)),
                ),
                SettingsSwitchRow(
                  icon: Icons.replay_rounded,
                  title: tr(context, 'Refresh when returning', 'Làm mới khi quay lại'),
                  subtitle: tr(context, 'Only when the data on screen is out of date.', 'Chỉ khi dữ liệu trên màn hình đã cũ.'),
                  value: _draft.onReturn,
                  onChanged: (v) => setState(() => _draft = _draft.copyWith(onReturn: v)),
                ),
                SettingsSwitchRow(
                  icon: Icons.sync_rounded,
                  title: tr(context, 'Background refresh', 'Làm mới nền'),
                  value: _draft.background,
                  onChanged: (v) => setState(() => _draft = _draft.copyWith(background: v)),
                ),
              ],
            ),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(context, 'Preferred background interval', 'Chu kỳ làm mới nền mong muốn'),
                      style: TextStyle(fontSize: 17, color: _draft.background ? c.textPrimary : c.textMuted)),
                  const SizedBox(height: 12),
                  IgnorePointer(
                    ignoring: !_draft.background,
                    child: Opacity(
                      opacity: _draft.background ? 1 : .45,
                      child: PillTabs<int>(
                        items: [
                          (30, tr(context, '30 min', '30 phút'), null),
                          (60, tr(context, '1 h', '1 giờ'), null),
                          (120, tr(context, '2 h', '2 giờ'), null),
                        ],
                        selected: _draft.intervalMinutes,
                        onChanged: (v) => setState(() => _draft = _draft.copyWith(intervalMinutes: v)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tr(context, 'The exact timing of background refresh is decided by Android/iOS (battery, usage, network). This is a preference, not a guaranteed schedule.',
                        'Thời điểm làm mới nền do Android/iOS quyết định (pin, mức sử dụng, mạng). Đây là mong muốn, không phải lịch chạy được bảo đảm.'),
                    style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
                  ),
                ],
              ),
            ),
            SettingsGroup(
              children: [
                SettingsSwitchRow(
                  icon: Icons.wifi_rounded,
                  title: tr(context, 'Wi-Fi only', 'Chỉ khi có Wi-Fi'),
                  subtitle: tr(context, 'Applies to automatic downloads by the app.', 'Áp dụng cho việc tải dữ liệu tự động của ứng dụng.'),
                  value: _draft.wifiOnly,
                  onChanged: (v) => setState(() => _draft = _draft.copyWith(wifiOnly: v)),
                ),
              ],
            ),
            InfoCard(
              icon: Icons.refresh_rounded,
              title: tr(context, 'Refresh now', 'Làm mới ngay'),
              body: tr(context, 'Pull down on Home to refresh the current place at any time.',
                  'Kéo xuống trên trang chủ để làm mới địa điểm đang xem bất cứ lúc nào.'),
            ),
          ],
        ),
      ),
    );
  }
}
