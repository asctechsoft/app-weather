import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import 'settings.dart';

/// Single conversion + formatting library used by every screen (spec UNIT01).
/// Inputs are canonical (°C, m/s, mm, hPa, m). Rounding happens once, at the end.
/// `null` always renders as "-".
class Fmt {
  Fmt(this.units, this.lang);

  factory Fmt.of(BuildContext context) {
    final s = SettingsScope.of(context);
    return Fmt(s.units, s.effectiveLanguage);
  }

  final UnitPrefs units;
  final String lang;
  static const dash = '-';

  // ---- conversions ----
  static double cToF(double c) => c * 1.8 + 32;
  static double msToKmh(double v) => v * 3.6;
  static double msToMph(double v) => v * 2.236936;
  static double msToKn(double v) => v * 1.943844;
  static double mmToIn(double v) => v / 25.4;
  static double kmToMi(double v) => v / 1.609344;
  static double hpaToInHg(double v) => v / 33.8639;
  static double hpaToMmHg(double v) => v * 0.750062;

  double? temp(double? c) => c == null ? null : (units.temperature == 'f' ? cToF(c) : c);

  /// Temperature difference: °F uses ×1.8 only (no +32).
  double? tempDelta(double? dc) => dc == null ? null : (units.temperature == 'f' ? dc * 1.8 : dc);

  double? wind(double? ms) {
    if (ms == null) return null;
    return switch (units.wind) {
      'ms' => ms,
      'mph' => msToMph(ms),
      'kn' => msToKn(ms),
      _ => msToKmh(ms),
    };
  }

  double? precip(double? mm) => mm == null ? null : (units.precipitation == 'in' ? mmToIn(mm) : mm);

  double? pressure(double? hpa) {
    if (hpa == null) return null;
    return switch (units.pressure) {
      'inhg' => hpaToInHg(hpa),
      'mmhg' => hpaToMmHg(hpa),
      _ => hpa,
    };
  }

  double? distance(double? m) {
    if (m == null) return null;
    final km = m / 1000;
    return units.distance == 'mi' ? kmToMi(km) : km;
  }

  // ---- unit labels ----
  String get tempUnit => units.temperature == 'f' ? '°F' : '°C';
  String get windUnit => switch (units.wind) { 'ms' => 'm/s', 'mph' => 'mph', 'kn' => 'kn', _ => 'km/h' };
  String get precipUnit => units.precipitation == 'in' ? 'in' : 'mm';
  String get pressureUnit => switch (units.pressure) { 'inhg' => 'inHg', 'mmhg' => 'mmHg', _ => 'hPa' };
  String get distanceUnit => units.distance == 'mi' ? 'mi' : 'km';

  // ---- number strings ----
  String deg(double? c) => c == null ? dash : '${temp(c)!.round()}°';
  String degU(double? c) => c == null ? dash : '${temp(c)!.round()}$tempUnit';
  String degDelta(double? dc) {
    final v = tempDelta(dc);
    if (v == null) return dash;
    final r = v.round();
    return '${r > 0 ? '+' : ''}$r°';
  }

  String windNum(double? ms) {
    final v = wind(ms);
    if (v == null) return dash;
    return units.wind == 'ms' ? v.toStringAsFixed(1) : v.round().toString();
  }

  String windU(double? ms) => ms == null ? dash : '${windNum(ms)} $windUnit';

  String precipNum(double? mm) {
    final v = precip(mm);
    if (v == null) return dash;
    return units.precipitation == 'in' ? v.toStringAsFixed(2) : v.toStringAsFixed(1);
  }

  String precipU(double? mm) => mm == null ? dash : '${precipNum(mm)} $precipUnit';

  String pressureNum(double? hpa) {
    final v = pressure(hpa);
    if (v == null) return dash;
    return units.pressure == 'inhg' ? v.toStringAsFixed(2) : v.round().toString();
  }

  String pressureU(double? hpa) => hpa == null ? dash : '${pressureNum(hpa)} $pressureUnit';

  String distanceNum(double? m) {
    final v = distance(m);
    if (v == null) return dash;
    return v >= 10 ? v.round().toString() : v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  }

  String distanceU(double? m) => m == null ? dash : '${distanceNum(m)} $distanceUnit';

  String pct(double? v) => v == null ? dash : '${v.round()}%';
  String uv(double? v) => v == null ? dash : (v - v.roundToDouble()).abs() < 0.05 ? v.round().toString() : v.toStringAsFixed(1);
  String number(double? v, {int digits = 0}) => v == null ? dash : v.toStringAsFixed(digits);

  // ---- time ----
  String get _locale => lang == 'vi' ? 'vi' : 'en_US';
  bool get _h24 => units.timeFormat == '24';

  /// Location-local DateTime from a UTC instant (IANA timezone of the place being viewed).
  static DateTime local(String isoUtc, String tzName) {
    final utc = DateTime.parse(isoUtc).toUtc();
    try {
      final loc = tz.getLocation(tzName);
      final t = tz.TZDateTime.from(utc, loc);
      return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
    } catch (_) {
      return utc;
    }
  }

  /// Wall-clock DateTime from the server's `localTime` ("YYYY-MM-DDTHH:mm").
  static DateTime wall(String localTime) => DateTime.parse(localTime.length == 16 ? '$localTime:00' : localTime);

  static DateTime dateOnly(String localDate) => DateTime.parse('${localDate}T00:00:00');

  String timeOf(DateTime t) => _h24 ? DateFormat('HH:mm', _locale).format(t) : DateFormat('h:mm a', _locale).format(t);
  String hourOf(DateTime t) => _h24 ? DateFormat('HH:mm', _locale).format(t) : DateFormat('h a', _locale).format(t);

  String time(String? isoUtc, String tzName) => isoUtc == null ? dash : timeOf(local(isoUtc, tzName));
  String wallTime(String? localTime) => localTime == null ? dash : timeOf(wall(localTime));
  String wallHour(String? localTime) => localTime == null ? dash : hourOf(wall(localTime));

  /// "Fri, Oct 9" / "T6, 9 thg 10"
  String dayShort(String localDate) => DateFormat(lang == 'vi' ? 'EEE, d MMM' : 'EEE, MMM d', _locale).format(dateOnly(localDate));
  String weekday(String localDate) => DateFormat('EEE', _locale).format(dateOnly(localDate));
  String monthDay(String localDate) => DateFormat(lang == 'vi' ? 'd MMM' : 'MMM d', _locale).format(dateOnly(localDate));
  String dayLong(String localDate) => DateFormat(lang == 'vi' ? 'EEEE, d MMMM' : 'EEEE, MMMM d', _locale).format(dateOnly(localDate));

  String duration(double? seconds) {
    if (seconds == null) return dash;
    final mins = (seconds / 60).round();
    return '${mins ~/ 60}h ${mins % 60}m';
  }
}
