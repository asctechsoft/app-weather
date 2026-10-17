import 'package:flutter/material.dart';

import '../core/models.dart';
import '../features/air/air_quality_screen.dart';
import '../features/alerts/alerts_screen.dart';
import '../features/astro/sun_moon_screen.dart';
import '../features/aurora/aurora_screen.dart';
import '../features/forecast/daily_screen.dart';
import '../features/forecast/hourly_screen.dart';
import '../features/map/map_screen.dart';
import '../features/metrics/feels_like_screen.dart';
import '../features/metrics/humidity_screen.dart';
import '../features/metrics/pressure_screen.dart';
import '../features/metrics/rain_screen.dart';
import '../features/metrics/uv_screen.dart';
import '../features/metrics/visibility_screen.dart';
import '../features/metrics/wind_screen.dart';
import '../features/places/places_screen.dart';
import '../features/places/search_screen.dart';
import '../features/settings/customize_home_screen.dart';
import '../features/settings/data_sources_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/widgets_screen.dart';

/// Typed route registry. Every screen receives the full [Location] so the place,
/// timezone and ID stay consistent across Home and detail screens.
class Routes {
  static Future<T?> _push<T>(BuildContext context, Widget page) =>
      Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

  static Future<void> hourly(BuildContext c, Location l, {String? date, String metric = 'temperature'}) =>
      _push(c, HourlyScreen(location: l, date: date, metric: metric));
  static Future<void> daily(BuildContext c, Location l) => _push(c, DailyScreen(location: l));
  static Future<void> wind(BuildContext c, Location l) => _push(c, WindScreen(location: l));
  static Future<void> rain(BuildContext c, Location l) => _push(c, RainScreen(location: l));
  static Future<void> humidity(BuildContext c, Location l) => _push(c, HumidityScreen(location: l));
  static Future<void> uv(BuildContext c, Location l) => _push(c, UvScreen(location: l));
  static Future<void> pressure(BuildContext c, Location l) => _push(c, PressureScreen(location: l));
  static Future<void> visibility(BuildContext c, Location l) => _push(c, VisibilityScreen(location: l));
  static Future<void> feelsLike(BuildContext c, Location l) => _push(c, FeelsLikeScreen(location: l));
  static Future<void> airQuality(BuildContext c, Location l) => _push(c, AirQualityScreen(location: l));
  static Future<void> sunMoon(BuildContext c, Location l) => _push(c, SunMoonScreen(location: l));
  static Future<void> aurora(BuildContext c, Location l) => _push(c, AuroraScreen(location: l));
  static Future<void> alerts(BuildContext c, Location l) => _push(c, AlertsScreen(location: l));
  static Future<void> map(BuildContext c, Location l) => _push(c, MapScreen(location: l));
  static Future<void> places(BuildContext c) => _push(c, const PlacesScreen());

  /// Opens search; resolves with the chosen [Location] (already added to saved places) or null.
  static Future<Location?> search(BuildContext c) => _push<Location>(c, const SearchScreen());
  static Future<void> settings(BuildContext c) => _push(c, const SettingsScreen());
  static Future<void> customizeHome(BuildContext c) => _push(c, const CustomizeHomeScreen());
  static Future<void> widgets(BuildContext c) => _push(c, const WidgetsScreen());
  static Future<void> dataSources(BuildContext c, Location? l) => _push(c, DataSourcesScreen(location: l));
}
