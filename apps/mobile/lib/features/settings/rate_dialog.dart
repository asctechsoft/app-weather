import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../ui/theme.dart';

/// RATE01 — neutral invitation. No star gating: everyone may rate or send feedback.
/// Auto prompt policy (proposed): after 5 sessions and 7 days, at most once per 90 days.
Future<void> maybeShowRatePrompt(BuildContext context) async {
  final s = SettingsScope.read(context);
  final first = DateTime.tryParse(s.firstUseAt ?? '');
  final last = DateTime.tryParse(s.lastRatePromptAt ?? '');
  final now = DateTime.now().toUtc();
  if (s.sessions < 5 || first == null || now.difference(first).inDays < 7) return;
  if (last != null && now.difference(last).inDays < 90) return;
  await s.markRatePrompted();
  if (context.mounted) await showRateDialog(context);
}

/// Store links are configured per release; until store IDs exist the button explains that.
const _androidStoreUrl = String.fromEnvironment('PLAY_STORE_URL');
const _iosStoreUrl = String.fromEnvironment('APP_STORE_URL');

Future<void> showRateDialog(BuildContext context, {VoidCallback? onFeedback}) {
  final c = SkyColors.of(context);
  final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  final storeName = isIos ? 'App Store' : 'Google Play';
  final url = isIos ? _iosStoreUrl : _androidStoreUrl;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(tr(context, 'Enjoying SkyWeather?', 'Bạn thấy SkyWeather thế nào?'))),
          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded), tooltip: tr(context, 'Close', 'Đóng')),
        ],
      ),
      content: Text(
        tr(context, 'A review on $storeName helps others find the app. You can also tell us directly what to improve.',
            'Một đánh giá trên $storeName giúp người khác biết đến ứng dụng. Bạn cũng có thể góp ý trực tiếp cho chúng tôi.'),
        style: TextStyle(color: c.textSecondary),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'Not now', 'Để sau'))),
        if (onFeedback != null)
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onFeedback();
            },
            child: Text(tr(context, 'Send feedback', 'Gửi góp ý')),
          ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            if (url.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(tr(context, 'Store listing is not available in this build yet.', 'Bản build này chưa có liên kết cửa hàng.')),
              ));
              return;
            }
            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          },
          child: Text(tr(context, 'Rate on $storeName', 'Đánh giá trên $storeName')),
        ),
      ],
    ),
  );
}
