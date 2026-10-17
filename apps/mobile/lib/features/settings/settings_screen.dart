import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../ui/routes.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'about_screen.dart';
import 'appearance_screen.dart';
import 'default_location_screen.dart';
import 'feedback_screen.dart';
import 'language_screen.dart';
import 'notifications_screen.dart';
import 'rate_dialog.dart';
import 'refresh_screen.dart';
import 'units_screen.dart';

/// SET01. Every row shows the SAVED value (never a draft) and opens a real destination.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final f = Fmt.of(context);
    final c = SkyColors.of(context);

    return DetailScaffold(
      title: tr(context, 'Settings', 'Cài đặt'),
      centerTitle: false,
      body: PageList(
        children: [
          SettingsGroup(
            title: tr(context, 'Preferences', 'Tùy chọn'),
            children: [
              SettingsRow(
                icon: Icons.language_rounded,
                title: tr(context, 'Language', 'Ngôn ngữ'),
                value: languageValueText(context, s),
                onTap: () => pushPage(context, const LanguageScreen()),
              ),
              SettingsRow(
                icon: Icons.thermostat_rounded,
                title: tr(context, 'Units', 'Đơn vị'),
                value: '${f.tempUnit} · ${f.windUnit}',
                onTap: () => pushPage(context, const UnitsScreen()),
              ),
              SettingsRow(
                icon: Icons.dark_mode_outlined,
                title: tr(context, 'Appearance', 'Giao diện'),
                value: themeLabel(context, s.appearance.theme),
                onTap: () => pushPage(context, const AppearanceScreen()),
              ),
              SettingsRow(
                icon: Icons.notifications_none_rounded,
                title: tr(context, 'Notifications', 'Thông báo'),
                value: tr(context, 'Not available', 'Chưa hỗ trợ'),
                onTap: () => pushPage(context, const NotificationsScreen()),
              ),
              SettingsRow(
                icon: Icons.place_outlined,
                title: tr(context, 'Default location', 'Vị trí mặc định'),
                value: defaultLocationText(context, s),
                onTap: () => pushPage(context, const DefaultLocationScreen()),
              ),
            ],
          ),
          SettingsGroup(
            title: tr(context, 'Experience', 'Trải nghiệm'),
            children: [
              SettingsRow(
                icon: Icons.home_outlined,
                title: tr(context, 'Customize Home', 'Tùy chỉnh trang chủ'),
                onTap: () => Routes.customizeHome(context),
              ),
              SettingsRow(
                icon: Icons.grid_view_rounded,
                title: tr(context, 'Widgets', 'Widget'),
                onTap: () => Routes.widgets(context),
              ),
              SettingsRow(
                icon: Icons.sync_rounded,
                title: tr(context, 'Refresh preferences', 'Tùy chọn làm mới'),
                onTap: () => pushPage(context, const RefreshScreen()),
              ),
            ],
          ),
          SettingsGroup(
            title: tr(context, 'App', 'Ứng dụng'),
            children: [
              SettingsRow(
                icon: Icons.description_outlined,
                title: tr(context, 'Privacy policy', 'Chính sách quyền riêng tư'),
                onTap: () => openLegal(context, 'privacyUrl', tr(context, 'Privacy policy', 'Chính sách quyền riêng tư')),
              ),
              SettingsRow(
                icon: Icons.article_outlined,
                title: tr(context, 'Terms of use', 'Điều khoản sử dụng'),
                onTap: () => openLegal(context, 'termsUrl', tr(context, 'Terms of use', 'Điều khoản sử dụng')),
              ),
              SettingsRow(
                icon: Icons.bar_chart_rounded,
                title: tr(context, 'Weather data & attribution', 'Dữ liệu thời tiết & ghi nguồn'),
                onTap: () => Routes.dataSources(context, null),
              ),
              SettingsRow(
                icon: Icons.star_outline_rounded,
                title: tr(context, 'Rate app', 'Đánh giá ứng dụng'),
                onTap: () => showRateDialog(context, onFeedback: () => pushPage(context, const FeedbackScreen())),
              ),
              SettingsRow(
                icon: Icons.chat_bubble_outline_rounded,
                title: tr(context, 'Send feedback', 'Gửi góp ý'),
                onTap: () => pushPage(context, const FeedbackScreen()),
              ),
              SettingsRow(
                icon: Icons.info_outline_rounded,
                title: tr(context, 'About', 'Giới thiệu'),
                onTap: () => pushPage(context, const AboutScreen()),
              ),
            ],
          ),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                snap.hasData ? '${tr(context, 'Version', 'Phiên bản')} ${snap.data!.version} (${snap.data!.buildNumber})' : '',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Legal URLs come from GET /v1/config per release + locale. Until they are published
  /// the row explains that instead of being a dead button.
  static Future<void> openLegal(BuildContext context, String key, String title) async {
    final lang = SettingsScope.read(context).effectiveLanguage;
    String? url;
    Object? error;
    try {
      final cfg = await ApiClient.instance.config(lang);
      url = s(jp(cfg, 'legal.$key'));
    } catch (e) {
      error = e;
    }
    if (!context.mounted) return;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri != null && uri.scheme == 'https') {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok || !context.mounted) return;
      error = Exception('launch');
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(error != null
            ? tr(context, 'The document could not be loaded right now. Check your connection and try again.',
                'Hiện không tải được tài liệu. Kiểm tra kết nối và thử lại.')
            : tr(context, 'Not published yet for this build. The document will be available here once it is published for this version.',
                'Bản build này chưa công bố tài liệu. Tài liệu sẽ có tại đây khi được công bố cho phiên bản này.')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'OK', 'Đồng ý')))],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared building blocks for the settings family of screens.
// ---------------------------------------------------------------------------

Future<T?> pushPage<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

String languageValueText(BuildContext context, AppSettings s) {
  String name(String code) => code == 'vi' ? 'Tiếng Việt' : 'English';
  if (s.language == 'system') return '${tr(context, 'System', 'Hệ thống')} (${name(s.deviceLanguage)})';
  return name(s.language);
}

String themeLabel(BuildContext context, String theme) => switch (theme) {
      'light' => tr(context, 'Light', 'Sáng'),
      'system' => tr(context, 'System', 'Hệ thống'),
      _ => tr(context, 'Dark', 'Tối'),
    };

String placeTitle(BuildContext context, Location l) =>
    l.name ?? (l.isGps ? tr(context, 'Current location', 'Vị trí hiện tại') : tr(context, 'Unnamed place', 'Địa điểm chưa có tên'));

String placeSubtitle(Location l) => [l.admin1, l.country].whereType<String>().where((e) => e.isNotEmpty).toSet().join(', ');

String defaultLocationText(BuildContext context, AppSettings s) {
  if (s.defaultMode == 'gps') return tr(context, 'Current location', 'Vị trí hiện tại');
  final l = s.defaultLocation;
  if (l == null) return tr(context, 'Not set', 'Chưa chọn');
  return placeTitle(context, l);
}

/// Eyebrow + one rounded card with divided rows (as in sc_setting.png).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 8), child: Eyebrow(title!)),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var k = 0; k < children.length; k++) ...[
                if (k > 0) Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: c.divider),
                children[k],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Icon + title (+ subtitle) + saved value + chevron.
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.icon, required this.title, this.subtitle, this.value, this.onTap, this.trailing, this.enabled = true});
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final fg = enabled ? c.textPrimary : c.textMuted;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: enabled ? c.textSecondary : c.textMuted, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 17, color: fg)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.3)),
                    ],
                  ],
                ),
              ),
              if (value != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: TextStyle(fontSize: 15, color: c.textSecondary)),
                  ),
                ),
              if (trailing != null)
                Padding(padding: const EdgeInsets.only(left: 8), child: trailing!)
              else if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: c.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Row with a switch; tapping the row toggles it. `onChanged == null` disables it.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({super.key, required this.icon, required this.title, this.subtitle, required this.value, required this.onChanged});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: SettingsRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

/// Single-choice row (custom radio, one selected per group).
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({super.key, required this.title, this.subtitle, required this.selected, this.onTap, this.leading});
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final enabled = onTap != null;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 14)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 17, color: enabled ? c.textPrimary : c.textMuted)),
                      if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? c.accent : (enabled ? c.textSecondary : c.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Coral full-width primary button.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: const Color(0xFF1A1020),
          disabledBackgroundColor: c.chipBg,
          disabledForegroundColor: c.textMuted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: c.textPrimary))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    );
  }
}

/// Scrollable content with a sticky bottom action (Save).
class BodyWithAction extends StatelessWidget {
  const BodyWithAction({super.key, required this.children, required this.action});
  final List<Widget> children;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: PageList(children: children)),
        SafeArea(
          top: false,
          child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: action),
        ),
      ],
    );
  }
}

Future<bool> confirmDiscard(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(context, 'Discard changes?', 'Bỏ thay đổi?')),
      content: Text(tr(context, 'Your changes have not been saved.', 'Các thay đổi của bạn chưa được lưu.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'Keep editing', 'Tiếp tục sửa'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'Discard', 'Bỏ thay đổi'))),
      ],
    ),
  );
  return r ?? false;
}

/// Asks Discard / Keep editing when leaving a draft screen with unsaved changes.
class DraftGuard extends StatelessWidget {
  const DraftGuard({super.key, required this.dirty, required this.child});
  final bool dirty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await confirmDiscard(context);
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: child,
    );
  }
}

/// Label + segmented pill choice; stacks on narrow screens (360 px).
class SegmentedSetting<T> extends StatelessWidget {
  const SegmentedSetting({super.key, required this.icon, required this.title, required this.items, required this.selected, required this.onChanged});
  final IconData icon;
  final String title;
  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: c.textSecondary, size: 24),
        const SizedBox(width: 14),
        Flexible(child: Text(title, style: TextStyle(fontSize: 17, color: c.textPrimary))),
      ],
    );
    final tabs = PillTabs<T>(
      items: [for (final (v, l) in items) (v, l, null)],
      selected: selected,
      onChanged: onChanged,
    );
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, box) {
          final inlineWidth = items.length * 78.0;
          if (box.maxWidth - inlineWidth >= 150) {
            return Row(children: [Expanded(child: label), SizedBox(width: inlineWidth, child: tabs)]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [label, const SizedBox(height: 12), tabs]);
        },
      ),
    );
  }
}
