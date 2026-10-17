import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'settings_screen.dart';

/// Language picker (SET01). Saves immediately and updates the whole app; places and cache stay.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final c = SkyColors.of(context);
    final device = s.deviceLanguage == 'vi' ? 'Tiếng Việt' : 'English';

    Future<void> pick(String v) async {
      if (v == s.language) return;
      await s.setLanguage(v);
    }

    return DetailScaffold(
      title: tr(context, 'Language', 'Ngôn ngữ'),
      centerTitle: false,
      body: PageList(
        children: [
          SettingsGroup(
            children: [
              ChoiceRow(
                title: tr(context, 'System', 'Theo hệ thống'),
                subtitle: tr(context, 'Currently $device', 'Hiện là $device'),
                selected: s.language == 'system',
                onTap: () => pick('system'),
              ),
              ChoiceRow(title: 'English', selected: s.language == 'en', onTap: () => pick('en')),
              ChoiceRow(title: 'Tiếng Việt', selected: s.language == 'vi', onTap: () => pick('vi')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              tr(context, 'Changing the language keeps your saved places and settings.', 'Đổi ngôn ngữ vẫn giữ các địa điểm và cài đặt đã lưu.'),
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
