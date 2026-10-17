import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/l10n.dart';
import '../core/models.dart';
import 'theme.dart';

/// Navy gradient page background.
class SkyBackground extends StatelessWidget {
  const SkyBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.bgTop, c.bgBottom])),
      child: child,
    );
  }
}

/// Standard detail page: back arrow, title, optional subtitle (usually the place), scrolling body.
class DetailScaffold extends StatelessWidget {
  const DetailScaffold({super.key, required this.title, this.subtitle, this.actions, required this.body, this.centerTitle = true});

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget body;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: tr(context, 'Back', 'Quay lại'),
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: c.blue, size: 22),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                        children: [
                          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: c.textPrimary)),
                          if (subtitle != null)
                            Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.textSecondary)),
                        ],
                      ),
                    ),
                    if (actions != null) ...actions! else const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// Translucent rounded card with a thin border.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.gradient, this.borderColor, this.margin});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final radius = BorderRadius.circular(18);
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: gradient == null ? c.card : null,
            gradient: gradient,
            borderRadius: radius,
            border: Border.all(color: borderColor ?? c.cardBorder),
          ),
          child: InkWell(borderRadius: radius, onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      ),
    );
  }
}

/// Card title row: "Hourly forecast ........ 24 hours >"
class CardHeader extends StatelessWidget {
  const CardHeader({super.key, required this.title, this.trailing, this.onTap, this.icon});
  final String title;
  final String? trailing;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: c.textSecondary), const SizedBox(width: 8)],
          Expanded(child: Text(title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: c.textPrimary))),
          if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 14, color: c.textSecondary)),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: c.textSecondary),
        ],
      ),
    );
  }
}

/// Inline explanation for a section that is empty / unsupported / stale / error.
class SectionNotice extends StatelessWidget {
  const SectionNotice({super.key, required this.status, this.reason, this.onRetry, this.compact = false});
  final String status;
  final String? reason;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final icon = switch (status) {
      'unsupported' => Icons.block_rounded,
      'stale' => Icons.history_rounded,
      'empty' => Icons.inbox_outlined,
      _ => Icons.error_outline_rounded,
    };
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 4 : 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.textMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(reasonText(context, status, reason), style: TextStyle(color: c.textSecondary, fontSize: 13))),
          if (onRetry != null && (status == 'error' || status == 'stale'))
            TextButton(onPressed: onRetry, child: Text(tr(context, 'Retry', 'Thử lại'))),
        ],
      ),
    );
  }
}

/// "Open-Meteo · model · Updated 9:41 AM" — every section shows its source and data time.
class SourceFooter extends StatelessWidget {
  const SourceFooter({super.key, required this.source, required this.timezone, this.prefix, this.stale = false});
  final SourceMeta? source;
  final String timezone;
  final String? prefix;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final f = Fmt.of(context);
    if (source == null) return const SizedBox.shrink();
    final parts = <String>[
      ?prefix,
      providerName(source!.providerId),
      dataKindLabel(context, source!.dataKind),
      if (source!.validAt != null) '${tr(context, 'Valid', 'Hiệu lực')} ${f.time(source!.validAt, timezone)}',
      if (source!.fetchedAt != null) '${tr(context, 'Updated', 'Cập nhật')} ${f.time(source!.fetchedAt, timezone)}',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(stale ? Icons.history_rounded : Icons.schedule_rounded, size: 14, color: stale ? c.accent : c.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              parts.join(' · ') + (stale ? ' · ${tr(context, 'may be out of date', 'có thể đã cũ')}' : ''),
              style: TextStyle(fontSize: 12, color: stale ? c.accent : c.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill segmented control (coral selection) used for Today/Tomorrow, tabs, unit choices.
class PillTabs<T> extends StatelessWidget {
  const PillTabs({super.key, required this.items, required this.selected, required this.onChanged, this.height = 44});

  final List<(T, String, IconData?)> items;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.chipBg.withValues(alpha: .6), borderRadius: BorderRadius.circular(height / 2), border: Border.all(color: c.cardBorder)),
      child: Row(
        children: [
          for (final (value, label, icon) in items)
            Expanded(
              child: Semantics(
                selected: value == selected,
                button: true,
                child: GestureDetector(
                  onTap: () => onChanged(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      gradient: value == selected ? SkyPalette.coralGradient : null,
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[Icon(icon, size: 18, color: value == selected ? const Color(0xFF1A1020) : c.textSecondary), const SizedBox(width: 6)],
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: value == selected ? const Color(0xFF1A1020) : c.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small stat tile: icon + label + big value + caption.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.label, required this.value, this.caption, this.iconColor, this.valueColor, this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  final Color? iconColor;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor ?? c.textSecondary, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: c.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: valueColor ?? c.textPrimary)),
                ),
                if (caption != null) Text(caption!, style: TextStyle(color: c.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: c.textMuted),
        ],
      ),
    );
  }
}

/// Info card "About pressure" style.
class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.title, required this.body, this.icon = Icons.info_outline_rounded});
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.textPrimary)),
                const SizedBox(height: 6),
                Text(body, style: TextStyle(color: c.textSecondary, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-page explanation for a capability that is not available in this build.
/// Never shows a fake switch or fake data.
class UnsupportedView extends StatelessWidget {
  const UnsupportedView({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: c.textMuted),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.textPrimary)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, height: 1.4)),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Loads data with loading / error+retry / pull-to-refresh states.
/// Responses from a superseded load are discarded (request generation).
class AsyncLoader<T> extends StatefulWidget {
  const AsyncLoader({super.key, required this.load, required this.builder, this.loadKey});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  /// Change this to force a new load (e.g. a different date).
  final Object? loadKey;

  @override
  State<AsyncLoader<T>> createState() => _AsyncLoaderState<T>();
}

class _AsyncLoaderState<T> extends State<AsyncLoader<T>> {
  final _gen = RequestGeneration();
  T? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AsyncLoader<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadKey != widget.loadKey) _load();
  }

  Future<void> _load() async {
    final g = _gen.next();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (!mounted || !_gen.isCurrent(g)) return;
      setState(() {
        _data = d;
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
    if (_loading && _data == null) {
      return Center(child: CircularProgressIndicator(color: c.accent));
    }
    if (_error != null && _data == null) {
      return UnsupportedView(
        icon: Icons.cloud_off_rounded,
        title: tr(context, 'Could not load', 'Không tải được dữ liệu'),
        message: errorText(context, _error!),
        action: FilledButton(onPressed: _load, child: Text(tr(context, 'Retry', 'Thử lại'))),
      );
    }
    return RefreshIndicator(
      color: c.accent,
      onRefresh: _load,
      child: widget.builder(context, _data as T, _load),
    );
  }
}

/// Standard scrolling list body with page padding.
class PageList extends StatelessWidget {
  const PageList({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 32)});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      children: [
        for (var k = 0; k < children.length; k++) ...[if (k > 0) const SizedBox(height: 14), children[k]],
      ],
    );
  }
}

/// Uppercase small section label ("PREFERENCES", "TWILIGHT").
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(letterSpacing: 2, fontSize: 13, fontWeight: FontWeight.w600, color: SkyColors.of(context).textSecondary),
      );
}

/// Displays a value or "-" with a short reason when null.
class ValueOrReason extends StatelessWidget {
  const ValueOrReason({super.key, required this.value, this.style, this.reason});
  final String value;
  final TextStyle? style;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    if (value != Fmt.dash) return Text(value, style: style);
    return Tooltip(
      message: reason ?? tr(context, 'Not available from the source', 'Nguồn chưa cung cấp'),
      child: Text(Fmt.dash, style: style),
    );
  }
}
