import 'package:flutter/material.dart';

/// SkyWeather design tokens (navy glass UI from the reference screens).
@immutable
class SkyColors extends ThemeExtension<SkyColors> {
  const SkyColors({
    required this.bgTop,
    required this.bgBottom,
    required this.card,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.blue,
    required this.divider,
    required this.chipBg,
  });

  final Color bgTop;
  final Color bgBottom;
  final Color card;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent; // coral
  final Color accentSoft;
  final Color blue;
  final Color divider;
  final Color chipBg;

  static const dark = SkyColors(
    bgTop: Color(0xFF0C1E3D),
    bgBottom: Color(0xFF06101F),
    card: Color(0xCC0E2142),
    cardBorder: Color(0xFF1E3A66),
    textPrimary: Color(0xFFF1F4FF),
    textSecondary: Color(0xFFB7C2EA),
    textMuted: Color(0xFF7E8DB8),
    accent: Color(0xFFF58A6E),
    accentSoft: Color(0x33F58A6E),
    blue: Color(0xFF5B8CFF),
    divider: Color(0xFF1B3358),
    chipBg: Color(0xFF13294D),
  );

  static const light = SkyColors(
    bgTop: Color(0xFFE6EEFB),
    bgBottom: Color(0xFFF6F8FD),
    card: Color(0xF2FFFFFF),
    cardBorder: Color(0xFFD5DFF0),
    textPrimary: Color(0xFF0F1D3A),
    textSecondary: Color(0xFF3D4E78),
    textMuted: Color(0xFF6B7A9E),
    accent: Color(0xFFE0603F),
    accentSoft: Color(0x22E0603F),
    blue: Color(0xFF2F64E0),
    divider: Color(0xFFDDE5F2),
    chipBg: Color(0xFFE8EEF8),
  );

  static SkyColors of(BuildContext context) => Theme.of(context).extension<SkyColors>()!;

  @override
  SkyColors copyWith() => this;

  @override
  SkyColors lerp(ThemeExtension<SkyColors>? other, double t) => t < 0.5 ? this : (other as SkyColors? ?? this);
}

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.dark ? SkyColors.dark : SkyColors.light;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: c.accent, brightness: b, primary: c.accent, surface: c.bgBottom),
    scaffoldBackgroundColor: c.bgBottom,
    extensions: [c],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.textPrimary, displayColor: c.textPrimary),
    iconTheme: IconThemeData(color: c.textPrimary),
    dividerColor: c.divider,
    appBarTheme: AppBarTheme(backgroundColor: Colors.transparent, foregroundColor: c.textPrimary, elevation: 0, scrolledUnderElevation: 0),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : c.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.blue : c.chipBg),
    ),
    snackBarTheme: SnackBarThemeData(backgroundColor: c.chipBg, contentTextStyle: TextStyle(color: c.textPrimary), behavior: SnackBarBehavior.floating),
    dialogTheme: DialogThemeData(backgroundColor: b == Brightness.dark ? const Color(0xFF0F2242) : Colors.white),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: b == Brightness.dark ? const Color(0xFF0D1E3B) : Colors.white),
  );
}

/// Category colors shared by charts and badges.
class SkyPalette {
  static const uv = [Color(0xFF3CCB7F), Color(0xFFF5D547), Color(0xFFFF9A3C), Color(0xFFF2545B), Color(0xFF9B59D0)];
  static const aqi = [Color(0xFF3CCB7F), Color(0xFFF5D547), Color(0xFFFF9A3C), Color(0xFFF2545B), Color(0xFF9B59D0), Color(0xFF7E2A3C)];
  static const coralGradient = LinearGradient(colors: [Color(0xFFFFA27E), Color(0xFFF06A5A)]);
  static const blueGradient = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF6FA0FF), Color(0xFF2E5BD8)]);

  static Color uvColor(String? c) => switch (c) {
        'low' => uv[0],
        'moderate' => uv[1],
        'high' => uv[2],
        'very_high' => uv[3],
        'extreme' => uv[4],
        _ => const Color(0xFF6B7A9E),
      };

  static Color aqiColor(String? c) => switch (c) {
        'good' => aqi[0],
        'moderate' => aqi[1],
        'unhealthy_sensitive' => aqi[2],
        'unhealthy' => aqi[3],
        'very_unhealthy' => aqi[4],
        'hazardous' => aqi[5],
        _ => const Color(0xFF6B7A9E), // null is never green
      };
}
